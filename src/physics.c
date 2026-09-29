// Ball physics using a soft step solver, after Box2D v3.
//
// Each fixed step builds contacts once (including speculative contacts for
// balls about to touch), then runs substeps of:
//   integrate velocities -> warm start -> solve with soft bias
//   -> integrate positions -> relax (solve without bias)
// followed by restitution. The bias pushes overlapping balls apart at a
// limited speed and the relax pass removes that push velocity again, so
// overlap from a merged planet growing is resolved without launching the balls
// around it. Warm starting keeps resting stacks rigid, so balls never need to
// be frozen.

#include "physics.h"

#include <math.h>
#include <string.h>

enum {
	WALL_LEFT = -1,
	WALL_RIGHT = -2,
	WALL_FLOOR = -3,
};

#define HASH_MASK (PHYS_HASH_SIZE - 1)

void phys_defaultConfig(PhysConfig* cfg)
{
	memset(cfg, 0, sizeof(*cfg));

	// Values converted from the original per-frame Lua physics running at 28fps.
	cfg->left = 160.0f;
	cfg->right = 400.0f;
	cfg->bottom = 240.0f;
	cfg->gravity = 235.2f;      // 0.3 px/frame^2
	cfg->airDrag = 0.28141f;    // v *= 0.99 per frame
	cfg->floorDrag = 1.43620f;  // vx *= 0.95 per frame on the floor
	cfg->ballRestitution = 0.45f;
	cfg->wallRestitution = 0.65f;
	cfg->restitutionThreshold = 20.0f;
	cfg->impactSpeed = 35.0f;

	// Solver tuning.
	cfg->contactHertz = 60.0f;
	cfg->contactDampingRatio = 3.0f;
	cfg->maxPushSpeed = 100.0f;
	cfg->linearSlop = 0.25f;
	cfg->speculativeDistance = 2.0f;

	cfg->mergeSlop = 1.0f;
	cfg->growSpeed = 25.0f;
	cfg->killLine = 40.0f;
	cfg->killTime = 1.0f;
	cfg->stepDt = 1.0f / 50.0f;
	cfg->substeps = 4;
	cfg->maxStepsPerUpdate = 3;
	cfg->maxLevel = 0;
	cfg->mergeEnabled = 1;
}

// Soft constraint coefficients, see b2MakeSoft in Box2D.
static void makeSoft(float hertz, float zeta, float h, float* biasRate, float* massScale, float* impulseScale)
{
	float omega = 2.0f * 3.14159265f * hertz;
	float a1 = 2.0f * zeta + h * omega;
	float a2 = h * omega * a1;
	float a3 = 1.0f / (1.0f + a2);

	*biasRate = omega / a1;
	*massScale = a2 * a3;
	*impulseScale = a3;
}

static void updateDerived(PhysWorld* w)
{
	const PhysConfig* c = &w->cfg;
	w->h = c->stepDt / (float)c->substeps;
	w->invH = 1.0f / w->h;
	w->airFactor = expf(-c->airDrag * w->h);
	w->floorFactor = expf(-c->floorDrag * c->stepDt);

	// Contacts can't be stiffer than the substep rate can resolve.
	float hertz = fminf(c->contactHertz, 0.25f * w->invH);
	makeSoft(hertz, c->contactDampingRatio, w->h, &w->biasRate, &w->massScale, &w->impulseScale);
	makeSoft(2.0f * hertz, c->contactDampingRatio, w->h, &w->staticBiasRate, &w->staticMassScale, &w->staticImpulseScale);
}

void phys_clear(PhysWorld* w)
{
	w->count = 0;
	w->freeCount = 0;

	for ( int id = 0; id < PHYS_MAX_BALLS; ++id )
	{
		w->idToIndex[id] = -1;
		w->freeIds[w->freeCount++] = id;
	}

	memset(w->warm, 0, sizeof(w->warm));
	w->warmStamp = 1;

	w->orderDirty = 1;
	w->contactCount = 0;
	w->eventCount = 0;
	w->accumulator = 0.0f;
	w->alpha = 1.0f;
	w->impact = 0;
	w->gameOver = 0;
}

void phys_init(PhysWorld* w, const PhysConfig* cfg)
{
	w->cfg = *cfg;
	updateDerived(w);
	phys_clear(w);
}

static float inverseMass(float r)
{
	// Mass is proportional to area so large planets push small ones around.
	return 100.0f / (r * r);
}

int phys_add(PhysWorld* w, float x, float y, float vx, float vy, int level, void* user)
{
	if ( w->freeCount == 0 || level < 1 || level > w->cfg.maxLevel )
		return -1;

	// Take the least recently freed id so warm start data from a removed ball
	// is never applied to a new one.
	int id = w->freeIds[0];
	memmove(&w->freeIds[0], &w->freeIds[1], (size_t)(w->freeCount - 1) * sizeof(int));
	--w->freeCount;

	int index = w->count++;
	PhysBall* b = &w->balls[index];

	memset(b, 0, sizeof(*b));
	b->x = b->ox = x;
	b->y = b->oy = y;
	b->vx = vx;
	b->vy = vy;
	b->level = level;
	b->r = b->targetR = w->cfg.radius[level];
	b->invMass = inverseMass(b->r);
	b->id = id;
	b->user = user;

	w->idToIndex[id] = index;
	w->orderDirty = 1;

	return id;
}

static void removeIndex(PhysWorld* w, int index)
{
	int last = w->count - 1;
	int id = w->balls[index].id;

	if ( index != last )
	{
		w->balls[index] = w->balls[last];
		w->idToIndex[w->balls[index].id] = index;
	}

	w->idToIndex[id] = -1;
	w->freeIds[w->freeCount++] = id;
	w->count--;
	w->orderDirty = 1;
}

void phys_remove(PhysWorld* w, int id)
{
	if ( id < 0 || id >= PHYS_MAX_BALLS || w->idToIndex[id] < 0 )
		return;

	removeIndex(w, w->idToIndex[id]);
}

PhysBall* phys_get(PhysWorld* w, int id)
{
	if ( id < 0 || id >= PHYS_MAX_BALLS || w->idToIndex[id] < 0 )
		return NULL;

	return &w->balls[w->idToIndex[id]];
}

// Insertion sort by left edge. Order barely changes between steps so this is
// close to linear.
static void sortOrder(PhysWorld* w)
{
	PhysBall* balls = w->balls;
	int* order = w->order;
	int n = w->count;

	if ( w->orderDirty )
	{
		for ( int i = 0; i < n; ++i )
			order[i] = i;

		w->orderDirty = 0;
	}

	for ( int a = 1; a < n; ++a )
	{
		int index = order[a];
		float key = balls[index].x - balls[index].r;
		int b = a - 1;

		while ( b >= 0 && balls[order[b]].x - balls[order[b]].r > key )
		{
			order[b + 1] = order[b];
			--b;
		}

		order[b + 1] = index;
	}
}

// --- Warm starting ---

static unsigned int hashSlot(int key)
{
	return (((unsigned int)key * 2654435761u) >> 20) & HASH_MASK;
}

static float warmImpulse(const PhysWorld* w, int key)
{
	unsigned int slot = hashSlot(key);

	while ( w->warm[slot].stamp == w->warmStamp )
	{
		if ( w->warm[slot].key == key )
			return w->warm[slot].impulse;

		slot = (slot + 1) & HASH_MASK;
	}

	return 0.0f;
}

static void storeImpulses(PhysWorld* w)
{
	uint32_t stamp = ++w->warmStamp;

	// PHYS_HASH_SIZE is at least twice PHYS_MAX_CONTACTS, so probing always
	// finds a free slot.
	for ( int k = 0; k < w->contactCount; ++k )
	{
		const PhysContact* ct = &w->contacts[k];

		if ( ct->impulse <= 0.0f )
			continue;

		unsigned int slot = hashSlot(ct->key);

		while ( w->warm[slot].stamp == stamp )
			slot = (slot + 1) & HASH_MASK;

		w->warm[slot].key = ct->key;
		w->warm[slot].stamp = stamp;
		w->warm[slot].impulse = ct->impulse;
	}
}

// --- Contacts ---

static void addContact(PhysWorld* w, int i, int j, int key, float nx, float ny, float s)
{
	if ( w->contactCount >= PHYS_MAX_CONTACTS )
		return;

	PhysBall* bi = &w->balls[i];
	float wj = 0.0f, vjx = 0.0f, vjy = 0.0f;

	if ( j >= 0 )
	{
		wj = w->balls[j].invMass;
		vjx = w->balls[j].vx;
		vjy = w->balls[j].vy;
	}

	PhysContact* ct = &w->contacts[w->contactCount++];
	ct->i = i;
	ct->j = j;
	ct->key = key;
	ct->nx = nx;
	ct->ny = ny;
	ct->s0 = s;
	ct->normalMass = 1.0f / (bi->invMass + wj);
	ct->impulse = warmImpulse(w, key);
	ct->maxImpulse = 0.0f;
	ct->vn0 = (vjx - bi->vx) * nx + (vjy - bi->vy) * ny;
}

static float speedBound(const PhysBall* b)
{
	return fabsf(b->vx) + fabsf(b->vy);
}

static void collide(PhysWorld* w)
{
	const PhysConfig* c = &w->cfg;
	PhysBall* balls = w->balls;
	int n = w->count;
	float dt = c->stepDt;
	float spec = c->speculativeDistance;
	float fastest = 0.0f;

	w->contactCount = 0;

	for ( int i = 0; i < n; ++i )
		fastest = fmaxf(fastest, speedBound(&balls[i]));

	sortOrder(w);

	// Contacts are created early enough to catch anything that could touch
	// during this step, so fast drops don't sink into the pile.
	float reach = spec + 2.0f * fastest * dt;

	for ( int a = 0; a < n; ++a )
	{
		int i = w->order[a];
		PhysBall* bi = &balls[i];
		float right = bi->x + bi->r + reach;

		for ( int k = a + 1; k < n; ++k )
		{
			int j = w->order[k];
			PhysBall* bj = &balls[j];

			if ( bj->x - bj->r > right )
				break;

			float margin = spec + (speedBound(bi) + speedBound(bj)) * dt;
			float rs = bi->r + bj->r;
			float limit = rs + margin;
			float dx = bj->x - bi->x;
			float dy = bj->y - bi->y;

			if ( dy >= limit || dy <= -limit )
				continue;

			float d2 = dx * dx + dy * dy;

			if ( d2 >= limit * limit )
				continue;

			float d = sqrtf(d2);
			float nx = 0.0f, ny = 1.0f;

			if ( d > 1e-4f )
			{
				nx = dx / d;
				ny = dy / d;
			}

			int lo = bi->id < bj->id ? bi->id : bj->id;
			int hi = bi->id < bj->id ? bj->id : bi->id;
			addContact(w, i, j, lo * 512 + hi, nx, ny, d - rs);
		}
	}

	for ( int i = 0; i < n; ++i )
	{
		PhysBall* b = &balls[i];
		float margin = spec + speedBound(b) * dt;
		float sLeft = (b->x - b->r) - c->left;
		float sRight = c->right - (b->x + b->r);
		float sFloor = c->bottom - (b->y + b->r);

		if ( sLeft < margin )
			addContact(w, i, WALL_LEFT, b->id * 512 + 256, -1.0f, 0.0f, sLeft);

		if ( sRight < margin )
			addContact(w, i, WALL_RIGHT, b->id * 512 + 257, 1.0f, 0.0f, sRight);

		if ( sFloor < margin )
			addContact(w, i, WALL_FLOOR, b->id * 512 + 258, 0.0f, 1.0f, sFloor);
	}
}

static void applyImpulse(PhysWorld* w, const PhysContact* ct, float impulse)
{
	PhysBall* bi = &w->balls[ct->i];
	float px = impulse * ct->nx;
	float py = impulse * ct->ny;

	bi->vx -= bi->invMass * px;
	bi->vy -= bi->invMass * py;

	if ( ct->j >= 0 )
	{
		PhysBall* bj = &w->balls[ct->j];
		bj->vx += bj->invMass * px;
		bj->vy += bj->invMass * py;
	}
}

static void warmStart(PhysWorld* w)
{
	for ( int k = 0; k < w->contactCount; ++k )
	{
		const PhysContact* ct = &w->contacts[k];

		if ( ct->impulse != 0.0f )
			applyImpulse(w, ct, ct->impulse);
	}
}

static void solve(PhysWorld* w, int useBias)
{
	const PhysConfig* c = &w->cfg;

	for ( int k = 0; k < w->contactCount; ++k )
	{
		PhysContact* ct = &w->contacts[k];
		PhysBall* bi = &w->balls[ct->i];
		float vjx = 0.0f, vjy = 0.0f, djx = 0.0f, djy = 0.0f;
		float biasRate = w->staticBiasRate;
		float softMass = w->staticMassScale;
		float softImpulse = w->staticImpulseScale;

		if ( ct->j >= 0 )
		{
			PhysBall* bj = &w->balls[ct->j];
			vjx = bj->vx;
			vjy = bj->vy;
			djx = bj->dx;
			djy = bj->dy;
			biasRate = w->biasRate;
			softMass = w->massScale;
			softImpulse = w->impulseScale;
		}

		// Current separation, tracked from displacement since the contact was built.
		float s = ct->s0 + (djx - bi->dx) * ct->nx + (djy - bi->dy) * ct->ny;
		float bias = 0.0f;
		float massScale = 1.0f;
		float impulseScale = 0.0f;

		if ( s > 0.0f )
		{
			// Speculative: allow closing the gap but no further.
			bias = s * w->invH;
		}
		else if ( useBias )
		{
			bias = fmaxf(biasRate * fminf(s + c->linearSlop, 0.0f), -c->maxPushSpeed);
			massScale = softMass;
			impulseScale = softImpulse;
		}

		float vn = (vjx - bi->vx) * ct->nx + (vjy - bi->vy) * ct->ny;
		float impulse = -ct->normalMass * massScale * (vn + bias) - impulseScale * ct->impulse;
		float newImpulse = fmaxf(ct->impulse + impulse, 0.0f);

		impulse = newImpulse - ct->impulse;
		ct->impulse = newImpulse;
		ct->maxImpulse = fmaxf(ct->maxImpulse, impulse);

		applyImpulse(w, ct, impulse);
	}
}

static void restitution(PhysWorld* w)
{
	const PhysConfig* c = &w->cfg;

	for ( int k = 0; k < w->contactCount; ++k )
	{
		PhysContact* ct = &w->contacts[k];

		if ( ct->maxImpulse <= 0.0f )
			continue;

		if ( ct->vn0 < -c->impactSpeed )
			w->impact = 1;

		if ( ct->vn0 > -c->restitutionThreshold )
			continue;

		PhysBall* bi = &w->balls[ct->i];
		float vjx = 0.0f, vjy = 0.0f;
		float e = c->wallRestitution;

		if ( ct->j >= 0 )
		{
			vjx = w->balls[ct->j].vx;
			vjy = w->balls[ct->j].vy;
			e = c->ballRestitution;
		}

		float vn = (vjx - bi->vx) * ct->nx + (vjy - bi->vy) * ct->ny;
		float impulse = -ct->normalMass * (vn + e * ct->vn0);
		float newImpulse = fmaxf(ct->impulse + impulse, 0.0f);

		impulse = newImpulse - ct->impulse;
		ct->impulse = newImpulse;
		ct->maxImpulse = fmaxf(ct->maxImpulse, impulse);

		applyImpulse(w, ct, impulse);
	}
}

// --- Step ---

static int pushEvent(PhysWorld* w, int type, int a, int b, int level, float x, float y)
{
	if ( w->eventCount >= PHYS_MAX_EVENTS )
		return 0;

	PhysEvent* e = &w->events[w->eventCount++];
	e->type = type;
	e->a = a;
	e->b = b;
	e->level = level;
	e->x = x;
	e->y = y;
	return 1;
}

static void resolveMerges(PhysWorld* w)
{
	const PhysConfig* c = &w->cfg;
	PhysBall* balls = w->balls;
	int n = w->count;
	int removed = 0;

	// Keep one event slot free for a game over.
	int eventLimit = PHYS_MAX_EVENTS - 1;

	sortOrder(w);

	for ( int i = 0; i < n; ++i )
		balls[i].merged = 0;

	for ( int a = 0; a < n && w->eventCount < eventLimit; ++a )
	{
		PhysBall* bi = &balls[w->order[a]];

		if ( bi->dead || bi->merged )
			continue;

		for ( int k = a + 1; k < n; ++k )
		{
			PhysBall* bj = &balls[w->order[k]];

			if ( bj->x - bj->r > bi->x + bi->r + c->mergeSlop )
				break;

			if ( bj->dead || bj->merged || bj->level != bi->level )
				continue;

			float dx = bj->x - bi->x;
			float dy = bj->y - bi->y;
			float reach = bi->r + bj->r + c->mergeSlop;

			if ( dx * dx + dy * dy > reach * reach )
				continue;

			// The lower ball survives, as in the original game.
			PhysBall* keep = (bi->y > bj->y) ? bi : bj;
			PhysBall* gone = (keep == bi) ? bj : bi;
			int newLevel = keep->level + 1;

			pushEvent(w, PHYS_EVENT_MERGE, keep->id, gone->id, newLevel, keep->x, keep->y);

			keep->merged = 1;
			gone->merged = 1;
			gone->dead = 1;
			++removed;

			if ( newLevel > c->maxLevel )
			{
				// Two of the largest planets cancel each other out.
				keep->dead = 1;
				++removed;
			}
			else
			{
				keep->level = newLevel;
				keep->targetR = c->radius[newLevel];
				keep->invMass = inverseMass(keep->targetR);
			}

			break;
		}
	}

	if ( removed > 0 )
	{
		for ( int i = w->count - 1; i >= 0; --i )
		{
			if ( w->balls[i].dead )
				removeIndex(w, i);
		}
	}
}

static void checkKillLine(PhysWorld* w)
{
	const PhysConfig* c = &w->cfg;

	for ( int i = 0; i < w->count && !w->gameOver; ++i )
	{
		PhysBall* b = &w->balls[i];

		if ( b->y >= c->killLine )
		{
			b->aboveTime = 0.0f;
			continue;
		}

		b->aboveTime += c->stepDt;

		if ( b->aboveTime >= c->killTime )
		{
			pushEvent(w, PHYS_EVENT_GAMEOVER, b->id, -1, b->level, b->x, b->y);
			w->gameOver = 1;
		}
	}
}

void phys_step(PhysWorld* w)
{
	const PhysConfig* c = &w->cfg;
	PhysBall* balls = w->balls;
	int n = w->count;
	float h = w->h;

	if ( w->gameOver )
		return;

	for ( int i = 0; i < n; ++i )
	{
		PhysBall* b = &balls[i];
		b->ox = b->x;
		b->oy = b->y;
		b->dx = 0.0f;
		b->dy = 0.0f;

		// Merged balls grow toward their new radius over a few frames.
		if ( b->r < b->targetR )
			b->r = fminf(b->r + c->growSpeed * c->stepDt, b->targetR);
	}

	collide(w);

	for ( int s = 0; s < c->substeps; ++s )
	{
		for ( int i = 0; i < n; ++i )
		{
			PhysBall* b = &balls[i];
			b->vy += c->gravity * h;
			b->vx *= w->airFactor;
			b->vy *= w->airFactor;
		}

		warmStart(w);
		solve(w, 1);

		for ( int i = 0; i < n; ++i )
		{
			PhysBall* b = &balls[i];
			float mx = b->vx * h;
			float my = b->vy * h;
			b->x += mx;
			b->y += my;
			b->dx += mx;
			b->dy += my;
		}

		solve(w, 0);
	}

	restitution(w);

	for ( int k = 0; k < w->contactCount; ++k )
	{
		const PhysContact* ct = &w->contacts[k];

		if ( ct->j == WALL_FLOOR && ct->maxImpulse > 0.0f )
			balls[ct->i].vx *= w->floorFactor;
	}

	storeImpulses(w);

	if ( c->mergeEnabled )
		resolveMerges(w);

	checkKillLine(w);
}

int phys_update(PhysWorld* w, float frameDt)
{
	const PhysConfig* c = &w->cfg;
	float maxDt = c->stepDt * (float)c->maxStepsPerUpdate;
	int steps = 0;

	w->eventCount = 0;
	w->impact = 0;

	if ( frameDt < 0.0f )
		frameDt = 0.0f;

	// After a long stall (system menu, loading) slow down instead of trying
	// to catch up all at once.
	if ( frameDt > maxDt )
		frameDt = maxDt;

	w->accumulator += frameDt;

	while ( w->accumulator >= c->stepDt && steps < c->maxStepsPerUpdate )
	{
		phys_step(w);
		w->accumulator -= c->stepDt;
		++steps;
	}

	if ( w->accumulator > c->stepDt )
		w->accumulator = c->stepDt;

	w->alpha = w->accumulator / c->stepDt;

	return steps;
}

void phys_renderPosition(const PhysWorld* w, const PhysBall* b, float* x, float* y)
{
	float t = w->alpha;
	*x = b->ox + (b->x - b->ox) * t;
	*y = b->oy + (b->y - b->oy) * t;
}
