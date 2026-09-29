CFLAGS = -std=c11 -O2 -Wall -Wextra -ffp-contract=off

physics_test: physics_test.c ../src/physics.c ../src/physics.h
	$(CC) $(CFLAGS) -o $@ physics_test.c ../src/physics.c -lm

run: physics_test
	./physics_test

clean:
	rm -f physics_test

.PHONY: run clean
