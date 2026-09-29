// Lua bindings for the ball physics.
//
// Exposes a global `physics` table to Lua. The C side owns ball positions and
// moves each ball's sprite directly after stepping, so Lua does no per-ball
// work each frame.

#include <math.h>
#include <stdlib.h>

#include "pd_api.h"
#include "physics.h"

static PlaydateAPI* pd = NULL;
static PhysWorld* world = NULL;

// Moves every ball sprite to its interpolated position. Sprites are only
// touched when their pixel position changes so resting balls cause no redraw.
static void renderSprites(void)
{
	for ( int i = 0; i < world->count; ++i )
	{
		PhysBall* b = &world->balls[i];

		if ( b->user == NULL )
			continue;

		float x, y;
		phys_renderPosition(world, b, &x, &y);

		int px = (int)floorf(x + 0.5f);
		int py = (int)floorf(y + 0.5f);

		if ( b->drawn && px == b->drawX && py == b->drawY )
			continue;

		b->drawX = px;
		b->drawY = py;
		b->drawn = 1;
		pd->sprite->moveTo((LCDSprite*)b->user, (float)px, (float)py);
	}
}

// physics.init(radius1, radius2, ...) sets the radius for each level and clears the world.
static int lua_init(lua_State* L)
{
	(void)L;
	PhysConfig cfg;
	phys_defaultConfig(&cfg);

	int levels = pd->lua->getArgCount();

	if ( levels > PHYS_MAX_LEVELS )
		levels = PHYS_MAX_LEVELS;

	for ( int i = 1; i <= levels; ++i )
		cfg.radius[i] = pd->lua->getArgFloat(i);

	cfg.maxLevel = levels;
	phys_init(world, &cfg);
	return 0;
}

// physics.setKillLine(y, seconds)
static int lua_setKillLine(lua_State* L)
{
	(void)L;
	world->cfg.killLine = pd->lua->getArgFloat(1);
	world->cfg.killTime = pd->lua->getArgFloat(2);
	return 0;
}

// physics.clear() removes every ball and forgets their sprites.
static int lua_clear(lua_State* L)
{
	(void)L;
	phys_clear(world);
	return 0;
}

// physics.add(x, y, vx, vy, level, sprite) -> id
static int lua_add(lua_State* L)
{
	(void)L;
	float x = pd->lua->getArgFloat(1);
	float y = pd->lua->getArgFloat(2);
	float vx = pd->lua->getArgFloat(3);
	float vy = pd->lua->getArgFloat(4);
	int level = pd->lua->getArgInt(5);
	LCDSprite* sprite = pd->lua->getSprite(6);

	int id = phys_add(world, x, y, vx, vy, level, sprite);

	if ( id < 0 )
	{
		pd->lua->pushNil();
		return 1;
	}

	pd->lua->pushInt(id);
	return 1;
}

// physics.remove(id)
static int lua_remove(lua_State* L)
{
	(void)L;
	phys_remove(world, pd->lua->getArgInt(1));
	return 0;
}

// physics.update(dt) -> eventCount, impact
// Advances the simulation by dt seconds of real time and moves the sprites.
static int lua_update(lua_State* L)
{
	(void)L;
	phys_update(world, pd->lua->getArgFloat(1));
	renderSprites();

	pd->lua->pushInt(world->eventCount);
	pd->lua->pushBool(world->impact);
	return 2;
}

// physics.event(i) -> type, a, b, level, x, y
// Events from the last update, 1-based. See PHYS_EVENT_* for types.
static int lua_event(lua_State* L)
{
	(void)L;
	int i = pd->lua->getArgInt(1) - 1;

	if ( i < 0 || i >= world->eventCount )
	{
		pd->lua->pushNil();
		return 1;
	}

	const PhysEvent* e = &world->events[i];
	pd->lua->pushInt(e->type);
	pd->lua->pushInt(e->a);
	pd->lua->pushInt(e->b);
	pd->lua->pushInt(e->level);
	pd->lua->pushFloat(e->x);
	pd->lua->pushFloat(e->y);
	return 6;
}

// physics.radius(id) -> current radius, target radius
static int lua_radius(lua_State* L)
{
	(void)L;
	PhysBall* b = phys_get(world, pd->lua->getArgInt(1));

	if ( b == NULL )
	{
		pd->lua->pushNil();
		return 1;
	}

	pd->lua->pushFloat(b->r);
	pd->lua->pushFloat(b->targetR);
	return 2;
}

// physics.count() -> number of balls
static int lua_count(lua_State* L)
{
	(void)L;
	pd->lua->pushInt(world->count);
	return 1;
}

static const lua_reg physicsLib[] = {
	{ "init", lua_init },
	{ "setKillLine", lua_setKillLine },
	{ "clear", lua_clear },
	{ "add", lua_add },
	{ "remove", lua_remove },
	{ "update", lua_update },
	{ "event", lua_event },
	{ "radius", lua_radius },
	{ "count", lua_count },
	{ NULL, NULL }
};

static const lua_val physicsConstants[] = {
	{ "kEventMerge", kInt, { .intval = PHYS_EVENT_MERGE } },
	{ "kEventGameOver", kInt, { .intval = PHYS_EVENT_GAMEOVER } },
	{ NULL, kInt, { .intval = 0 } }
};

#ifdef _WINDLL
__declspec(dllexport)
#endif
int eventHandler(PlaydateAPI* playdate, PDSystemEvent event, uint32_t arg)
{
	(void)arg;

	if ( event == kEventInitLua )
	{
		pd = playdate;

		if ( world == NULL )
		{
			world = pd->system->realloc(NULL, sizeof(PhysWorld));
			PhysConfig cfg;
			phys_defaultConfig(&cfg);
			phys_init(world, &cfg);
		}

		const char* err;

		if ( !pd->lua->registerClass("physics", physicsLib, physicsConstants, 1, &err) )
			pd->system->error("%s:%i: registerClass failed, %s", __FILE__, __LINE__, err);
	}

	return 0;
}
