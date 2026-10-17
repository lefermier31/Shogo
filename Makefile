CC := i686-w64-mingw32-gcc
CFLAGS := -O2 -std=gnu11 -Wall -Wextra -Wno-cast-function-type -mno-sse -mfpmath=387 -fno-strict-aliasing
LDFLAGS := -shared -static-libgcc -s -Wl,--nxcompat -ladvapi32

SRC := src/main.c src/log.c src/pe.c src/timing.c src/servertick.c src/mousefix.c src/nocrit.c src/camguard.c

all: dist/ShogoFPS.asi

dist/ShogoFPS.asi: $(SRC) src/shogofps.h
	@mkdir -p dist
	$(CC) $(CFLAGS) $(SRC) -o $@ $(LDFLAGS)

test: dist/ShogoFPS.asi
	./tests/run_tests.sh

clean:
	rm -f dist/ShogoFPS.asi

.PHONY: all test clean
