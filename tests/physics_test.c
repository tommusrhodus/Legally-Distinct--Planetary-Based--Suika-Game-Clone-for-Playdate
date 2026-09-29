// Host-side tests and benchmarks for src/physics.c.
//
//   make -C tests run

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../src/physics.h"

static const float kRadius[] = { 0, 10, 14, 16, 18, 20, 22, 26, 30, 34, 40, 48 };
static const int kMaxLevel = 11;

static int failures = 0;

#define CHECK(cond, ...) do { \
	if ( !(cond) ) { printf("  FAIL: "); printf(__VA_ARGS__); printf("\n"); ++failures; } \
	else { printf("  ok:   "); printf(__VA_ARGS__); printf("\n"); } \
} while (0)

static unsigned int rngState = 12345;

static unsigned int rng(void)
{
	rngState = rngState * 1664525u + 1013904223u;
	return rngState >> 8;
}

static int randInt(int lo, int hi)
{
	return lo + (int)(rng() % (unsigned int)(hi - lo + 1));
}

static void makeWorld(PhysWorld* w, int mergeEnabled)
{
	PhysConfig cfg;
	phys_defaultConfig(&cfg);

	for ( int i = 1; i <= kMaxLevel; ++i )
		cfg.radius[i] = kRadius[i];

	cfg.maxLevel = kMaxLevel;
	cfg.mergeEnabled = mergeEnabled;
	phys_init(w, &cfg);
}

static void runSeconds(PhysWorld* w, float seconds)
{
	int steps = (int)(seconds / w->cfg.stepDt + 0.5f);

	for ( int i = 0; i < steps; ++i )
		phys_step(w);
}

static float maxOverlap(const PhysWorld* w)
{
	float worst = 0.0f;

	for ( int i = 0; i < w->count; ++i )
	{
		for ( int j = i + 1; j < w->count; ++j )
		{
			const PhysBall* a = &w->balls[i];
			const PhysBall* b = &w->balls[j];
			float d = sqrtf((a->x - b->x) * (a->x - b->x) + (a->y - b->y) * (a->y - b->y));
			float o = a->r + b->r - d;

			if ( o > worst )
				worst = o;
		}
	}

	return worst;
}

static float maxSpeed(const PhysWorld* w)
{
	float worst = 0.0f;

	for ( int i = 0; i < w->count; ++i )
	{
		float s = sqrtf(w->balls[i].vx * w->balls[i].vx + w->balls[i].vy * w->balls[i].vy);

		if ( s > worst )
			worst = s;
	}

	return worst;
}

static int outOfBounds(const PhysWorld* w)
{
	for ( int i = 0; i < w->count; ++i )
	{
		const PhysBall* b = &w->balls[i];

		if ( !isfinite(b->x) || !isfinite(b->y) )
			return 1;

		if ( b->x < w->cfg.left + b->r - 1.0f || b->x > w->cfg.right - b->r + 1.0f || b->y > w->cfg.bottom - b->r + 1.0f )
			return 1;
	}

	return 0;
}

// Reference: the original per-frame Lua integration for a lone ball at 28fps.
static void originalDrop(float r, float* firstHit, float* apex, float* apexTime)
{
	float y = 15, vx = 0.1f, vy = 4.0f;
	int hit = 0;
	*apex = 1e9f;

	for ( int frame = 1; frame < 28 * 10; ++frame )
	{
		vy += 0.3f;
		vx *= 0.99f;
		vy *= 0.99f;
		y += vy;

		if ( y > 240 - r )
		{
			vy = -vy * 0.65f;
			y = 240 - r;
			vx *= 0.95f;

			if ( hit == 1 )
				return;

			if ( !hit )
			{
				*firstHit = frame / 28.0f;
				hit = 1;
			}
		}
		else if ( hit && y < *apex )
		{
			*apex = y;
			*apexTime = frame / 28.0f;
		}
	}
}

static void testSingleDropMatchesOriginal(void)
{
	printf("single ball drop vs original 28fps integration\n");

	float r = kRadius[5];
	float refHit = 0, refApex = 0, refApexTime = 0;
	originalDrop(r, &refHit, &refApex, &refApexTime);

	PhysWorld* w = calloc(1, sizeof(PhysWorld));
	makeWorld(w, 1);
	int id = phys_add(w, 280, 15, 0.1f * 28, 4.0f * 28, 5, NULL);

	float hit = -1, apex = 1e9f, apexTime = 0;
	int bounced = 0;

	for ( int step = 1; step < 50 * 10; ++step )
	{
		phys_step(w);
		PhysBall* b = phys_get(w, id);
		float t = step * w->cfg.stepDt;

		if ( hit < 0 && b->y >= 240 - r - 0.01f )
			hit = t;

		if ( hit >= 0 && b->vy < 0 )
			bounced = 1;

		if ( bounced && b->y < apex )
		{
			apex = b->y;
			apexTime = t;
		}

		if ( bounced && b->vy > 0 && b->y >= 240 - r - 0.01f )
			break;
	}

	printf("  original: first floor hit %.3fs, bounce apex y=%.1f at %.3fs\n", refHit, refApex, refApexTime);
	printf("  new:      first floor hit %.3fs, bounce apex y=%.1f at %.3fs\n", hit, apex, apexTime);
	CHECK(fabsf(hit - refHit) < 0.05f, "first floor hit within 50ms of original (%.3f vs %.3f)", hit, refHit);
	CHECK(fabsf(apex - refApex) < 6.0f, "bounce apex within 6px of original (%.1f vs %.1f)", apex, refApex);

	free(w);
}

static void dropRandomBalls(PhysWorld* w, int count, float interval, int maxLevel)
{
	for ( int i = 0; i < count && !w->gameOver; ++i )
	{
		int level = randInt(1, maxLevel);
		float r = kRadius[level];
		float x = 160 + r + (float)randInt(0, (int)(240 - 2 * r));
		phys_add(w, x, 15, 0.1f * 28, 4.0f * 28, level, NULL);
		runSeconds(w, interval);
	}
}

static void testPileSettles(void)
{
	printf("pile of balls settles without freezing (merging disabled)\n");

	PhysWorld* w = calloc(1, sizeof(PhysWorld));
	makeWorld(w, 0);
	w->cfg.killTime = 1e9f; // Let the pile grow past the line for this test.
	rngState = 777;

	dropRandomBalls(w, 45, 0.4f, 7);
	runSeconds(w, 8.0f);

	// Track jitter over one more second.
	float startX[PHYS_MAX_BALLS], startY[PHYS_MAX_BALLS];

	for ( int i = 0; i < w->count; ++i )
	{
		startX[i] = w->balls[i].x;
		startY[i] = w->balls[i].y;
	}

	float worstSpeed = 0.0f;

	for ( int s = 0; s < 50; ++s )
	{
		phys_step(w);
		float sp = maxSpeed(w);

		if ( sp > worstSpeed )
			worstSpeed = sp;
	}

	float drift = 0.0f;

	for ( int i = 0; i < w->count; ++i )
	{
		float d = fabsf(w->balls[i].x - startX[i]) + fabsf(w->balls[i].y - startY[i]);

		if ( d > drift )
			drift = d;
	}

	float overlap = maxOverlap(w);
	printf("  balls=%d maxSpeed=%.3fpx/s drift/1s=%.3fpx overlap=%.3fpx\n", w->count, worstSpeed, drift, overlap);
	CHECK(w->count == 45, "all 45 balls still in the world");
	CHECK(!outOfBounds(w), "no ball outside the container or NaN");
	CHECK(worstSpeed < 2.0f, "settled pile max speed below 2px/s (%.3f)", worstSpeed);
	CHECK(drift < 0.5f, "settled pile moves less than half a pixel per second (%.3f)", drift);
	CHECK(overlap < 1.0f, "max overlap below 1px (%.3f)", overlap);

	free(w);
}

static void testSupportRemovedPileCollapses(void)
{
	printf("removing a supporting ball lets the balls above fall (no frozen floaters)\n");

	PhysWorld* w = calloc(1, sizeof(PhysWorld));
	makeWorld(w, 0);
	w->cfg.killTime = 1e9f;

	int bottom = phys_add(w, 280, 240 - 20, 0, 0, 5, NULL);
	int top = phys_add(w, 280, 240 - 60, 0, 0, 5, NULL);
	runSeconds(w, 1.0f);
	float before = phys_get(w, top)->y;
	phys_remove(w, bottom);
	runSeconds(w, 3.0f);
	float after = phys_get(w, top)->y;

	printf("  top ball y before=%.1f after=%.1f\n", before, after);
	CHECK(fabsf(after - (240.0f - 20.0f)) < 0.1f, "top ball fell to the floor after its support was removed");

	free(w);
}

static void testMergeRules(void)
{
	printf("merge rules\n");

	PhysWorld* w = calloc(1, sizeof(PhysWorld));
	makeWorld(w, 1);

	int lower = phys_add(w, 250, 240 - 10, 0, 0, 1, NULL);
	int upper = phys_add(w, 250, 240 - 40, 0, 0, 1, NULL);
	int merges = 0, keep = -1, gone = -1, level = 0;

	for ( int s = 0; s < 100 && merges == 0; ++s )
	{
		phys_update(w, w->cfg.stepDt);

		for ( int e = 0; e < w->eventCount; ++e )
		{
			if ( w->events[e].type == PHYS_EVENT_MERGE )
			{
				++merges;
				keep = w->events[e].a;
				gone = w->events[e].b;
				level = w->events[e].level;
			}
		}
	}

	CHECK(merges == 1, "two touching moons merge once");
	CHECK(keep == lower && gone == upper, "the lower ball survives");
	CHECK(level == 2, "survivor levels up to 2");
	CHECK(w->count == 1 && phys_get(w, upper) == NULL, "removed ball is gone from the world");

	PhysBall* b = phys_get(w, lower);
	runSeconds(w, 0.5f);
	CHECK(fabsf(b->r - kRadius[2]) < 0.01f, "survivor grows to the level 2 radius (%.2f)", b->r);

	// Two of the largest planets cancel out.
	phys_clear(w);
	phys_add(w, 200, 240 - 48, 0, 0, kMaxLevel, NULL);
	phys_add(w, 300, 240 - 48, 0, 0, kMaxLevel, NULL);
	int finalLevel = 0;

	for ( int s = 0; s < 100 && w->count > 0; ++s )
	{
		phys_update(w, w->cfg.stepDt);

		for ( int e = 0; e < w->eventCount; ++e )
			finalLevel = w->events[e].level;
	}

	CHECK(w->count == 0 && finalLevel == kMaxLevel + 1, "two max level planets remove each other");

	free(w);
}

static void testMergeInPileDoesNotExplode(void)
{
	printf("merging inside a full container pushes neighbours without launching them\n");

	float worstUp = 0.0f;

	for ( unsigned int seed = 1; seed <= 4; ++seed )
	{
		PhysWorld* w = calloc(1, sizeof(PhysWorld));
		makeWorld(w, 0);
		w->cfg.killTime = 1e9f;
		rngState = seed * 31u;

		// The largest growth in the game is a sun (r=40) becoming a black hole (r=48).
		int big = phys_add(w, 280, 240 - kRadius[10], 0, 0, 10, NULL);
		runSeconds(w, 1.0f);
		dropRandomBalls(w, 45, 0.3f, 4);
		runSeconds(w, 6.0f);

		PhysBall* b = phys_get(w, big);
		b->level = 11;
		b->targetR = kRadius[11];
		b->invMass = 100.0f / (b->targetR * b->targetR);

		for ( int s = 0; s < 150; ++s )
		{
			phys_step(w);

			for ( int i = 0; i < w->count; ++i )
			{
				if ( -w->balls[i].vy > worstUp )
					worstUp = -w->balls[i].vy;
			}
		}

		if ( outOfBounds(w) )
			++failures;

		free(w);
	}

	// For scale: a ball dropped from the top bounces off the floor at about 150px/s.
	printf("  peak upward speed after a 40->48 merge under a full pile: %.1fpx/s\n", worstUp);
	CHECK(worstUp < 150.0f, "merge pushes neighbours less than a floor bounce would (%.1f)", worstUp);
}

static void testKillLine(void)
{
	printf("game over when a ball rests above the kill line\n");

	PhysWorld* w = calloc(1, sizeof(PhysWorld));
	makeWorld(w, 1);

	// A freshly dropped ball passes through the line without ending the game.
	phys_add(w, 280, 15, 2.8f, 112.0f, 3, NULL);
	int over = 0;

	for ( int s = 0; s < 150; ++s )
	{
		phys_update(w, w->cfg.stepDt);
		over |= w->gameOver;
	}

	CHECK(!over, "a dropped ball falling through the line does not end the game");

	// Fill with balls so the pile reaches above the line.
	rngState = 4242;
	float t = 0.0f;
	int gameOverId = -1;

	for ( int i = 0; i < 200 && gameOverId < 0; ++i )
	{
		int level = randInt(6, 9);
		float r = kRadius[level];
		phys_add(w, 160 + r + (float)randInt(0, (int)(240 - 2 * r)), 15, 2.8f, 112.0f, level, NULL);

		for ( int s = 0; s < 65 && gameOverId < 0; ++s )
		{
			phys_update(w, w->cfg.stepDt);
			t += w->cfg.stepDt;

			for ( int e = 0; e < w->eventCount; ++e )
			{
				if ( w->events[e].type == PHYS_EVENT_GAMEOVER )
					gameOverId = w->events[e].a;
			}
		}
	}

	PhysBall* killer = phys_get(w, gameOverId);
	CHECK(gameOverId >= 0 && killer != NULL, "game over reported after %.1fs with %d balls", t, w->count);
	CHECK(killer && killer->y < w->cfg.killLine, "the reported ball is above the line (y=%.1f)", killer ? killer->y : 0);

	free(w);
}

static void testInterpolation(void)
{
	printf("fixed step accumulator and interpolation\n");

	PhysWorld* w = calloc(1, sizeof(PhysWorld));
	makeWorld(w, 1);
	phys_add(w, 280, 100, 0, 50, 1, NULL);

	int s1 = phys_update(w, 0.010f);
	CHECK(s1 == 0 && fabsf(w->alpha - 0.5f) < 1e-4f, "half a step of time gives no step and alpha 0.5");
	int s2 = phys_update(w, 0.030f);
	CHECK(s2 == 2 && fabsf(w->alpha) < 1e-4f, "accumulated time runs two steps");
	int s3 = phys_update(w, 1.0f);
	CHECK(s3 == w->cfg.maxStepsPerUpdate, "a long stall is capped at %d steps", w->cfg.maxStepsPerUpdate);

	free(w);
}

static void runGameplay(unsigned int seed, int* merges, int* maxLevelSeen, float* gameTime, float* peakOverlap)
{
	PhysWorld* w = calloc(1, sizeof(PhysWorld));
	makeWorld(w, 1);
	rngState = seed;
	*merges = 0;
	*maxLevelSeen = 0;
	*peakOverlap = 0.0f;
	float t = 0.0f;

	while ( !w->gameOver && t < 900.0f )
	{
		int level = randInt(1, 5);
		float r = kRadius[level];
		phys_add(w, 160 + r + (float)randInt(0, (int)(240 - 2 * r)), 15, 2.8f, 112.0f, level, NULL);

		// Players can drop roughly every 1.3s.
		for ( int s = 0; s < 65 && !w->gameOver; ++s )
		{
			phys_update(w, w->cfg.stepDt);
			t += w->cfg.stepDt;

			for ( int e = 0; e < w->eventCount; ++e )
			{
				if ( w->events[e].type == PHYS_EVENT_MERGE )
				{
					++*merges;

					if ( w->events[e].level > *maxLevelSeen )
						*maxLevelSeen = w->events[e].level;
				}
			}
		}

		float o = maxOverlap(w);

		if ( o > *peakOverlap )
			*peakOverlap = o;

		if ( outOfBounds(w) )
		{
			printf("  out of bounds at t=%.1f\n", t);
			++failures;
			break;
		}
	}

	*gameTime = t;
	free(w);
}

static void testGameplaySoak(void)
{
	printf("random-drop gameplay soak\n");

	for ( unsigned int seed = 1; seed <= 5; ++seed )
	{
		int merges, maxLevel;
		float t, overlap;
		runGameplay(seed * 7919u, &merges, &maxLevel, &t, &overlap);
		printf("  seed %u: lasted %.0fs, %d merges, highest level %d, peak overlap between drops %.2fpx\n", seed, t, merges, maxLevel, overlap);
		CHECK(overlap < 3.0f, "overlap stays small (%.2f)", overlap);
	}
}

static void benchmark(void)
{
	printf("benchmark\n");

	PhysWorld* w = calloc(1, sizeof(PhysWorld));
	makeWorld(w, 0);
	w->cfg.killTime = 1e9f;
	rngState = 31337;
	dropRandomBalls(w, 120, 0.25f, 3);
	runSeconds(w, 5.0f);

	int steps = 5000;
	clock_t start = clock();

	for ( int i = 0; i < steps; ++i )
		phys_step(w);

	double us = (double)(clock() - start) / CLOCKS_PER_SEC * 1e6 / steps;
	printf("  %d balls: %.2fus per 50Hz step on this host (%d substeps)\n", w->count, us, w->cfg.substeps);

	free(w);
}

int main(void)
{
	testSingleDropMatchesOriginal();
	testPileSettles();
	testSupportRemovedPileCollapses();
	testMergeRules();
	testMergeInPileDoesNotExplode();
	testKillLine();
	testInterpolation();
	testGameplaySoak();
	benchmark();

	printf("\n%s (%d failures)\n", failures ? "FAILED" : "PASSED", failures);
	return failures ? 1 : 0;
}
