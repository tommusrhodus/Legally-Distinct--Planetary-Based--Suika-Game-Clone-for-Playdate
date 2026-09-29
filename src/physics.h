// Ball physics for the planet merge game.
//
// Pure C with no Playdate dependency so it can be unit tested on the host.
// All units are pixels and seconds.

#ifndef PHYSICS_H
#define PHYSICS_H

#include <stdint.h>

#define PHYS_MAX_BALLS 256
#define PHYS_MAX_LEVELS 16
#define PHYS_MAX_EVENTS 64
#define PHYS_MAX_CONTACTS 2048
#define PHYS_HASH_SIZE 4096 // Power of two, at least twice PHYS_MAX_CONTACTS.

typedef struct {
	int key;
	uint32_t stamp; // Entry is valid only when this matches PhysWorld.warmStamp.
	float impulse;
} PhysWarmEntry;

enum {
	PHYS_EVENT_MERGE = 1,
	PHYS_EVENT_GAMEOVER = 2,
};

typedef struct {
	int type;
	int a;     // merge: surviving ball id. gameover: id of the ball that ended the game.
	int b;     // merge: removed ball id.
	int level; // merge: survivor's new level. Greater than maxLevel means both balls were removed.
	float x, y;
} PhysEvent;

typedef struct {
	float x, y;   // Position at the end of the most recent step.
	float ox, oy; // Position at the end of the previous step, for render interpolation.
	float vx, vy;
	float dx, dy; // Displacement since the start of the current step.
	float r, targetR;
	float invMass;
	float aboveTime; // Continuous time spent with the centre above the kill line.
	int level;
	int id;
	uint8_t merged;   // Set while merges are resolved so each ball merges at most once per step.
	uint8_t dead;
	void* user;       // Opaque pointer owned by the caller (the ball's sprite).
	int drawX, drawY; // Last pixel position handed to the renderer.
	uint8_t drawn;
} PhysBall;

typedef struct {
	int i;          // Ball index.
	int j;          // Ball index, or a negative WALL_* value for the container.
	int key;        // Stable pair key for warm starting.
	float nx, ny;   // Unit normal pointing from i toward j.
	float s0;       // Separation when the contact was created. Negative means overlap.
	float normalMass;
	float impulse;  // Accumulated normal impulse.
	float maxImpulse;
	float vn0;      // Relative normal velocity at the start of the step. Negative when approaching.
} PhysContact;

typedef struct {
	float left, right, bottom;
	float gravity;              // px/s^2
	float airDrag;              // 1/s, applied as v *= exp(-airDrag * dt)
	float floorDrag;            // 1/s, horizontal damping while resting on the floor
	float ballRestitution;
	float wallRestitution;
	float restitutionThreshold; // px/s. Slower impacts don't bounce.
	float impactSpeed;          // px/s. Approach speed that counts as an audible impact.
	float contactHertz;         // Stiffness of contact recovery.
	float contactDampingRatio;
	float maxPushSpeed;         // px/s. Fastest that overlapping balls are pushed apart.
	float linearSlop;           // px. Overlap allowed at rest, reduces jitter.
	float speculativeDistance;  // px. Contacts are created this far before touching.
	float mergeSlop;            // px. Same-level balls this close count as touching.
	float growSpeed;            // px/s. How fast a merged ball grows to its new radius.
	float killLine;             // y. A ball whose centre stays above this line...
	float killTime;             // ...for this many seconds ends the game.
	float stepDt;               // Fixed simulation step.
	int substeps;
	int maxStepsPerUpdate;      // Caps catch-up work after a slow frame.
	float radius[PHYS_MAX_LEVELS + 1]; // Radius per level, 1-based.
	int maxLevel;
	int mergeEnabled;
} PhysConfig;

typedef struct {
	PhysConfig cfg;

	PhysBall balls[PHYS_MAX_BALLS];
	int count;

	int idToIndex[PHYS_MAX_BALLS]; // -1 when the id is free.
	int freeIds[PHYS_MAX_BALLS];
	int freeCount;

	int order[PHYS_MAX_BALLS]; // Ball indices sorted by left edge, for sweep and prune.
	int orderDirty;

	PhysContact contacts[PHYS_MAX_CONTACTS];
	int contactCount;

	// Impulses from the previous step, keyed by contact pair, for warm starting.
	// Bumping warmStamp empties the table without touching it.
	PhysWarmEntry warm[PHYS_HASH_SIZE];
	uint32_t warmStamp;

	PhysEvent events[PHYS_MAX_EVENTS];
	int eventCount;

	float accumulator;
	float alpha; // Interpolation factor between the previous and current step.
	int impact;  // Set when an impact faster than impactSpeed happened since the last update.
	int gameOver;

	// Derived from the config.
	float h, invH;
	float airFactor, floorFactor;
	float biasRate, massScale, impulseScale;                   // Ball contacts.
	float staticBiasRate, staticMassScale, staticImpulseScale; // Walls.
} PhysWorld;

void phys_defaultConfig(PhysConfig* cfg);
void phys_init(PhysWorld* w, const PhysConfig* cfg);
void phys_clear(PhysWorld* w);

// Returns the new ball's id, or -1 if the world is full or the level is invalid.
int phys_add(PhysWorld* w, float x, float y, float vx, float vy, int level, void* user);
void phys_remove(PhysWorld* w, int id);
PhysBall* phys_get(PhysWorld* w, int id);

// Runs one fixed simulation step.
void phys_step(PhysWorld* w);

// Advances the simulation by frameDt seconds of real time using fixed steps and
// updates alpha for interpolation. Returns the number of steps taken.
int phys_update(PhysWorld* w, float frameDt);

// Interpolated render position of a ball.
void phys_renderPosition(const PhysWorld* w, const PhysBall* b, float* x, float* y);

#endif
