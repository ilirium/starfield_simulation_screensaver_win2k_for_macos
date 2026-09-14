# Reverse engineering `bin/ssstars.scr`

Everything below was recovered from the stripped PE32 binary with
`llvm-objdump -d`. Addresses are virtual (ImageBase `0x01000000`).

The binary itself is not committed — these notes are the record of it, and are
what `StarfieldEngine.swift` is checked against.

## Why the drawing is squares

The entire GDI32 import table is three functions:

    GetClipBox, PatBlt, GetStockObject

No `SetPixel`, no `LineTo`, no `BitBlt`. Stars are axis-aligned rectangles
filled by `PatBlt` — erased with `BLACKNESS` (`0x42`, call at `0x10016fa`) and
drawn with `WHITENESS` (`0xFF0062`, call at `0x10017f7`). Hence no
antialiasing in the port.

## Globals

| Address | Meaning |
|---|---|
| `0x1008800[i]` | star X, signed, relative to center |
| `0x1008b20[i]` | star Y |
| `0x1008e40[i]` | star Z |
| `0x10087f0` / `0x10087f2` | center X / Y (word) |
| `0x10087f4` | star count (Density) |
| `0x10087f6` / `0x1009162` | screen width / height |
| `0x10083c0` / `0x10083c8` | current speed / target speed |
| `0x1009160` | WarpSpeed setting, 0..10 |
| `0x10087ec` | RNG state |

Arrays are indexed by `starIndex * 4` (`shll $0x2, %esi` at `0x10016a4`), so
they are `int32` and sized for the 200-star maximum.

## Projection (`0x10016a9`)

    leal (%eax,%eax,4), %eax    ; x * 5
    shll $0x9, %eax             ; << 9   -> x * 2560
    cltd; idivl %ebx            ; / z

so `screenX = x * 2560 / z + centerX`, same for Y. Truncating signed
division — the steppiness near the center is original behavior, not a bug.

## Star size (`0x10016e3`)

    movl $0xa00, %eax   ; 2560
    subl %ebx, %eax     ; 2560 - z
    movl $0x280, %ebx   ; 640
    cltd; idivl %ebx
    incl %eax           ; + 1

`size = (2560 - z) / 640 + 1`, i.e. 1..5 pixels, used as both width and
height of the `PatBlt` rectangle.

## Speed ramp (`0x1001700`)

    if speed < target { speed++ } else if speed > target { speed-- }
    z -= speed; if z < 0 { z = 0 }
    if z == 0 { respawn }

This sits *inside* the per-star loop, so the ramp advances once per star per
tick rather than once per frame. The port keeps that.

`target` is computed at `0x1001935` as `(WarpSpeed + 1) * 10` → 10..110.

## Respawn (`0x1001c5a`)

    x = rand() % screenWidth  - centerX
    y = rand() % screenHeight - centerY
    z = 0xA00                                ; 2560

Because the spawn Z equals the projection scale, a new star appears exactly
at its random screen position and then moves outward. The binary tests
`screenWidth != 0` before *both* the X and the Y branch (`0x1001c8c` repeats
the `0x10087f6` compare); the port keeps the quirk.

## RNG (`0x1001c41`)

    seed = seed * 0x343FD + 0x269EC3
    return seed >> 16

The Visual C++ runtime's `rand()`, inlined. The CRT seeds it to 1; the port
seeds from the system RNG so two launches differ.

## Settings (`0x1001d52`)

Two `GetPrivateProfileIntW` calls against `control.ini`:

| Key | Default | Clamp |
|---|---|---|
| `WarpSpeed` | 5 | `> 10` resets to 5 |
| `Density` | 25 | clamped to 10..200 |

The setup dialog drives these with a scrollbar (`SetScrollRange`/`SetScrollPos`)
and an up-down control (`fmsctls_updown32`).

## Frame rate

`SetTimer(hwnd, 1, 50, NULL)` at `0x100194b`, interval read from the word at
`0x1006088` = 50 ms, so 20 fps.

## Deliberate deviations in the port

1. **Star scale.** The 1..5 px sizes were tuned for a 640 px wide CRT. On a
   modern display the port multiplies by `width / 640`. Set `starScale` to
   `1.0` in `StarfieldView.swift` for pixel-exact output.
2. **Full redraw per frame** instead of erase-rect-then-draw-rect. Visually
   identical, but overlapping stars no longer punch holes in each other.
3. **RNG seeding**, as above.

Everything else — constants, integer math, clamps, ramp placement — matches.
