# How the screen saver was taken apart

`NOTES.md` is the reference: every constant with the address it came from.
This is the other half — the order things happened in, the tools, and the two
places the reasoning went sideways before it went right.

The whole job was done on an Apple Silicon Mac with nothing but the Command
Line Tools. No Ghidra, no IDA, no radare2, no Windows, no emulator. The binary
was never executed. Everything below is static analysis of 33 KB of 2003-era
x86.

## 1. What is this thing

```
$ file bin/ssstars.scr
bin/ssstars.scr: PE32 executable (GUI) Intel 80386 (stripped to external PDB), for MS Windows
```

Three useful facts in one line. **PE32/i386** means a 32-bit Windows binary, so
the disassembler needs `coff-i386`, not the arm64 this machine speaks.
**GUI subsystem** means it has a window and a message loop. **Stripped to
external PDB** is the bad news: no symbols. Every function is an address and
nothing more.

## 2. Read the strings first, always

Strings are free. Before decoding a single instruction, it is worth knowing
what the program says about itself:

```
$ strings -a bin/ssstars.scr
...
VerifyScreenSavePwd
scr\ssstars.dbg
```

That confirmed a screen saver and named the missing debug file. But the
interesting text — dialog labels, registry paths, version info — was missing,
because Windows resources are UTF-16LE and `strings` looks for runs of ASCII.
Every other byte being `00` breaks the run.

On Linux this is `strings -el`. **macOS `strings` has no `-el`.** So:

```python
import re
d = open('bin/ssstars.scr','rb').read()
for m in re.finditer(rb'(?:[\x20-\x7e]\x00){5,}', d):
    print(m.group().decode('utf-16-le', 'ignore'))
```

Five or more printable-ASCII-then-NUL pairs. Crude, and it misses anything
non-Latin, but it immediately produced the program's self-description:

```
Starfield Simulation
Starfield Simulation Setup
Starfield &Density
Number of stars (10-200)
&Warp Speed
Density
WarpSpeed
5.00.2195.6601
Microsoft(R) Windows (R) 2000 Operating System
Control Panel\Desktop
fmsctls_updown32
```

Now the shape of the problem is known before any disassembly: two settings
named `Density` and `WarpSpeed`, a documented density range of 10–200, and a
spin control (`fmsctls_updown32`) in a setup dialog. The rest of the work was
finding where those numbers go.

## 3. The import table is the map

A stripped binary has no symbols of its own, but it must name every function
it borrows from the system — otherwise the loader could not link it. **The
import table is free symbol information, and it is always there.**

`llvm-objdump --private-headers` printed the directory offsets but only one
DLL name, so I parsed the table by hand: read `e_lfanew` at `0x3c`, walk the
section headers to build an RVA→file-offset map, then walk the import
descriptors, following each `OriginalFirstThunk` to the hint/name entries and
counting `FirstThunk` forward to get the IAT address of every function.

Ninety imports came out. One block mattered more than all the rest:

```
--- GDI32.dll ---
  01001018 GetClipBox
  0100101c PatBlt
  01001020 GetStockObject
```

**That is the entire graphics vocabulary of the program.** Three functions.

No `SetPixel`. No `LineTo`. No `BitBlt`, no `StretchBlt`, no DIB calls, no
OpenGL, no DirectDraw. `PatBlt` fills a rectangle with the current brush, and
`GetStockObject` is how you fetch a stock white or black one.

So the stars were never points and never lines. **They are filled
rectangles.** That single observation fixed the visual character of the port —
hard-edged aliased squares, not antialiased dots — and it was established
before reading one instruction of drawing code. It also promised that the
render loop would be small, because there is very little you can build out of
three GDI calls.

## 4. Follow the call site

`PatBlt`'s IAT slot is `0x0100101c`. Any call to it compiles to an indirect
call through that address, so the drawing code can be found by grepping for
the address rather than by reading the program top to bottom:

```
$ llvm-objdump -d --no-show-raw-insn bin/ssstars.scr > dis.txt
$ grep -n '100101c' dis.txt
744:  10016fa:  calll  *0x100101c
822:  10017f7:  calll  *0x100101c
```

Two call sites, 253 bytes apart, almost certainly the two halves of one
loop. That is the whole render path. Everything after this was reading 112
instructions carefully.

## 5. Decoding the math

The block before the first call:

```asm
movl  0x1008800(%esi), %eax    ; X[i]   -- esi = i*4
movl  0x1008e40(%esi), %ebx    ; Z[i]
leal  (%eax,%eax,4), %eax      ; x * 5
shll  $0x9, %eax               ; << 9   -> x * 2560
cltd                           ; sign-extend for idiv
idivl %ebx                     ; / z
movl  %eax, %ecx
movzwl 0x10087f0, %eax         ; centerX
addl  %eax, %ecx
```

`lea (%eax,%eax,4)` is the classic compiler idiom for ×5 — it costs one cycle
where a multiply would cost several. Followed by a shift of 9 (×512), it is
×2560. So:

    screenX = x * 2560 / z + centerX

`cltd; idivl` is **signed, truncating** division. Not a rounding artifact to
be cleaned up — it is what gives the original its slightly steppy motion near
the center, and the port reproduces it exactly.

The array bases fell out of the addressing. `esi` is `i << 2`, so these are
`int32` arrays: `0x1008800` is X, `0x1008b20` is Y, `0x1008e40` is Z. The
gap between each is `0x320` = 800 bytes = 200 entries, matching the documented
200-star maximum exactly. A nice independent confirmation that the array
identification was right.

Star size, just before the call:

```asm
movl  $0xa00, %eax    ; 2560
subl  %ebx, %eax      ; 2560 - z
movl  $0x280, %ebx    ; 640
cltd
idivl %ebx
incl  %eax            ; + 1
```

`size = (2560 - z) / 640 + 1`, so 1 to 5, used as both the width and the
height of the rectangle.

## 6. The raster-op codes name the two halves

`PatBlt`'s last argument is a raster operation. The two call sites push
different ones:

| Site | ROP pushed | Meaning |
|---|---|---|
| `0x10016fa` | `0x42` | `BLACKNESS` |
| `0x10017f7` | `0xFF0062` | `WHITENESS` |

So the loop is erase-then-draw: paint the star's **old** rectangle black,
advance it, paint its **new** rectangle white. No full-screen clear per frame —
which is exactly how you make a starfield run on a 2003 machine.

(The port departs here, redrawing the frame in full. It looks identical and
avoids one original artifact: overlapping stars punching black holes in each
other. Recorded in NOTES.md with the other two deviations.)

## 7. Two calls into the unknown

Between the erase and the draw sit a speed ramp and two `call`s to addresses
with no names. Both turned out to be short.

`0x1001c5a` — respawn:

```
x = rand() % screenWidth  - centerX
y = rand() % screenHeight - centerY
z = 0xA00                                ; 2560
```

The spawn Z is `0xA00`, and so is the projection scale. That is not a
coincidence, it is the trick: at `z == 2560` the perspective divide is the
identity, so a new star appears **exactly** at its random screen position and
then moves outward from there. Uniform screen-space seeding, no trigonometry,
no square roots.

`0x1001c41` — six instructions:

```asm
movl   0x10087ec, %eax
imull  $0x343fd, %eax, %eax
addl   $0x269ec3, %eax
movl   %eax, 0x10087ec
shrl   $0x10, %eax
retl
```

`0x343FD` is 214013 and `0x269EC3` is 2531011 — the multiplier and increment
of the Visual C++ runtime's `rand()`. The CRT function was inlined into the
saver. (It returns 16 bits here rather than the CRT's usual 15; the callers
zero-extend `%ax`.)

## 8. Where I guessed wrong

**The warp setting is not a checkbox.** The resource strings say `&Warp
Speed`, and the target speed is computed as `(word[0x1009160] + 1) * 10`. I
read that as a boolean: off gives 10, on gives 20. A 2× warp seemed weak, but
plausible.

It was wrong, and the fix came from grepping every reference to that address
instead of only reading the one site that used it:

```
$ grep -n '1009160' dis.txt
 10019b7:  decw   0x1009160
 10019c0:  incw   0x1009160
 10019de:  movw   $0xa, 0x1009160
 1001d6f:  movw   $0x5, 0x1009160
```

Increment, decrement, and constants of 10 and 5. Nothing boolean does that.
`0x1009160` is a **0–10 slider** defaulting to 5, which is why the imports
include `SetScrollRange` and `SetScrollPos`. Target speed therefore runs
10–110, not 10–20.

The lesson is mundane and kept paying out: **a single read of a global tells
you how it is used once, not what it is.** Grep every reference before naming
it.

The second misstep was pure tooling. Extracting a function with
`awk '/^ 1001c5a:/,/^ 1001d20:/'` dumped 188 KB — the range pattern re-triggers
and the end address never matched as written. `grep -n` for the start line and
then `sed -n 'A,Bp'` is unglamorous and does not surprise you.

## 9. Settings, and the last strings

Two `GetPrivateProfileIntW` calls, back to back:

```asm
pushl $0x5            ; default
pushl $0x1006020      ; key name
...
cmpw  $0xa, %ax
jbe   ...
movw  $0x5, 0x1009160 ; > 10 -> reset to 5

pushl $0x19           ; default 25
pushl $0x1006038
...
cmpw  $0xc8, %ax      ; clamp to 200
...
cmpw  $0xa, %ax       ; clamp to 10
```

The key names are pointers into `.data`. Converting VA to file offset with the
section map from step 3 (`.data` is VA `0x6000` at raw `0x4e00`) and running
the UTF-16 reader at those two addresses gave `WarpSpeed` and `Density` —
closing the loop back to the strings from step 2.

The frame rate came from the `SetTimer` call: the interval is loaded from a
word in `.data` at `0x1006088`, which reads 50. Fifty milliseconds, 20 fps.

## 10. Proving the reading was right

A disassembly you cannot test is a guess. The check was to implement the
recovered algorithm, render frames offscreen, and composite 26 of them with a
per-pixel `max()`.

If the projection were wrong, that image would show drift, shear, or stars
converging on the wrong point. What it shows is stars streaking radially
outward from the center, each one growing as it approaches — which is only
what `x * 2560 / z` produces if the divide, the center offset, and the size
ramp are all correct together.

That composite is checked in as the regression test for the port.

## What was not done

Only the simulation was recovered. Untouched: the dialog procedure, the
message loop, the preview and password paths (`VerifyScreenSavePwd`,
`PASSWORD.CPL`), the `WinHelp` wiring, and the CRT startup code — which is
most of the 18 KB of `.text`. The 112 instructions between the two `PatBlt`
calls are the entire interesting part of the program, and finding them took
far less effort than reading the binary front to back would have.

## Summary of method

1. `file` — establish architecture and whether symbols exist.
2. Strings, **both encodings** — let the program describe itself for free.
3. Parse the import table — borrowed symbols are the map of a stripped binary.
4. Read the import list for what is *absent*; three GDI calls said more than
   any amount of disassembly would have.
5. Grep the IAT slot of an interesting import to jump straight to the code
   that matters.
6. Decode the arithmetic idioms (`lea` multiplies, shifts, `cltd; idiv`).
7. Grep *every* reference to a global before naming it.
8. Reimplement, render, and look at the picture.
