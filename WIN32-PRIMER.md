# The Windows side

`HOW-IT-WORKS.md` explains the macOS port by mapping it onto Win32, which is
only useful if you already know Win32. This file supplies that half. It
assumes you can program, and assumes nothing about Windows.

It is also the missing key to `TEARDOWN.md`: several things in the disassembly
— why pushing arguments backwards matters, what an "IAT slot" is, why grepping
for one address found the drawing code — only make sense once the Win32
machinery underneath is visible.

---

## 1. Win32 is a C API from 1993

There are no objects. There are functions, structures, and **handles**.

A handle is an opaque integer identifying something the operating system owns
on your behalf. You never see inside it. You pass it back to the API to say
"that one".

| Handle | Refers to |
|---|---|
| `HWND` | a window |
| `HDC` | a *device context* — a surface you can draw on |
| `HINSTANCE` | a loaded module (your EXE or a DLL) |
| `HBRUSH` | a fill pattern or color |

The naming conventions are relentless and, once learned, genuinely helpful:
`H` prefix for handles, `LP` for "long pointer", `W`/`DW` for word and
double-word. `WPARAM` and `LPARAM` are two general-purpose integer parameters
carried by every window message, whose meaning changes per message.

This is the API `ssstars.scr` was built against, and the one the disassembly is
full of.

---

## 2. A Windows GUI program is a loop that receives messages

This is *the* central idea, and it is what macOS discards.

Windows does not call your code when something happens. Instead, everything —
a keystroke, a mouse move, a repaint request, a timer firing — becomes a
**message** placed in a queue belonging to your program. A message is a small
struct: which window, which message number, and two parameters.

Your program's job is to pull messages out of that queue forever:

```c
MSG msg;
while (GetMessage(&msg, NULL, 0, 0)) {
    TranslateMessage(&msg);
    DispatchMessage(&msg);
}
```

`GetMessage` blocks until a message arrives and returns 0 only when the
program should quit. `DispatchMessage` hands it to the right window's
**window procedure** — a callback you wrote:

```c
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE:  /* window just created */   return 0;
    case WM_DESTROY: /* window going away */     return 0;
    case WM_SIZE:    /* someone resized us */    return 0;
    case WM_TIMER:   /* a timer fired */         return 0;
    }
    return DefWindowProc(hwnd, msg, wp, lp);   /* everything else */
}
```

The final line matters: there are *hundreds* of message types, and you handle
the four you care about and hand the rest to the system's default
implementation. A Win32 program is a giant `switch` statement, and the message
loop is its engine.

Before any of this you must **register a window class** — a template naming
your `WndProc`, an icon, a cursor — and then create a window from it:

```c
RegisterClassW(&wc);
CreateWindowExW(...);
```

The original does all of this. Its imports include `RegisterClassW`,
`CreateWindowExW`, `GetMessageW`, `TranslateMessage`, `DispatchMessageW`,
`DefWindowProcW`, and `PostQuitMessage` — the message loop, complete, visible
in the import table. Its window class name appears in the resource strings as
`WindowsScreenSaverClass`.

### The actual switch, recovered

Here is the beginning of the real window procedure from `ssstars.scr`, at
address `0x1001650`. `%eax` holds the message number:

```asm
decl  %eax                  ; msg - 1
je    0x10018d7             ;   == 1   -> WM_CREATE
decl  %eax                  ; msg - 2
je    0x10018c0             ;   == 2   -> WM_DESTROY
subl  $0x3, %eax            ; msg - 5
je    0x10018a9             ;   == 5   -> WM_SIZE
subl  $0x10e, %eax          ; msg - 0x113
jne   0x1001956             ;   != 0x113 -> DefWindowProc
```

The compiler turned the `switch` into successive subtractions, each testing
for zero. Working the arithmetic backwards gives the four cases: **1**
(`WM_CREATE`), **2** (`WM_DESTROY`), **5** (`WM_SIZE`), and **0x113**
(`WM_TIMER`). Anything else falls through to `DefWindowProc`.

That is the whole program's control flow, in eight instructions. `WM_SIZE`
records the screen dimensions; `WM_TIMER` draws a frame.

---

## 3. Timers deliver messages, they do not call you

```c
SetTimer(hwnd, 1, 50, NULL);
```

"Every 50 milliseconds, post a `WM_TIMER` message to this window." There is no
callback thread and no interrupt — the message lands in the same queue as
mouse clicks, and gets handled by the same `switch`. This is why a Win32 app
that stops pumping messages freezes completely: the clock stops too.

`WM_TIMER` is also **low priority**. Windows only synthesizes one when the
queue is otherwise empty, and never stacks them up. If your drawing overruns
the interval you silently lose ticks rather than falling behind forever.

The original hedges anyway. After drawing it calls:

```c
PeekMessageW(&msg, hwnd, 0x113, 0x113, PM_REMOVE);
```

`PeekMessage` is the non-blocking sibling of `GetMessage`, here filtered to
the range `0x113`–`0x113` — only `WM_TIMER` — with `PM_REMOVE` to discard what
it finds. It is throwing away any timer message that piled up while the frame
was being drawn, so a slow frame cannot cause a burst of catch-up frames.

---

## 4. Drawing: device contexts and GDI

The drawing API is **GDI** (Graphics Device Interface), in `GDI32.DLL`.

Everything is drawn through an `HDC`, a *device context*. It is a handle to a
drawable surface plus the current drawing state — current brush, current pen,
current text color. It is roughly a `Canvas` object with the fields hidden
behind an integer.

The usual way to draw is to handle `WM_PAINT` between `BeginPaint` and
`EndPaint`. **The original does not do that.** Its imports have no
`BeginPaint`; instead it uses:

```c
HDC hdc = GetDC(hwnd);
/* ...draw... */
ReleaseDC(hwnd, hdc);
```

`GetDC` grabs a context for the window's client area at any time, outside the
painting cycle. For a screen saver — which owns the whole screen, is never
partly obscured, and repaints on its own schedule — this is simpler and
faster. You can see it in the disassembly: `GetDC` at `0x1001685` immediately
inside the `WM_TIMER` branch, `ReleaseDC` at `0x100181b` after the loop.

### Brushes and stock objects

GDI fills shapes with the **currently selected brush**. Rather than create
one, the program borrows a system-owned brush:

```c
GetStockObject(WHITE_BRUSH);
```

Stock objects are preallocated, shared, and need never be freed. For a program
whose entire palette is black and white, that is the whole graphics setup.

---

## 5. `PatBlt` and raster operations

This is the call the stars are made of, and the one that gave the whole
teardown away.

```c
BOOL PatBlt(HDC hdc, int x, int y, int w, int h, DWORD rop);
```

"Fill the rectangle at (x, y) sized w×h." The interesting parameter is the
last one. A **raster operation** code specifies how the source pattern
combines with what is already on the surface — Boolean algebra on pixels,
from the era when that was how you got effects cheaply.

| ROP | Value | Effect |
|---|---|---|
| `BLACKNESS` | `0x00000042` | fill with black, ignore everything |
| `WHITENESS` | `0x00FF0062` | fill with white, ignore everything |
| `PATCOPY` | `0x00F00021` | copy the current brush |
| `DSTINVERT` | `0x00550009` | invert what is there |
| `PATINVERT` | `0x005A0049` | XOR the brush with the destination |

The two `PatBlt` calls in the render loop push `0x42` and `0xFF0062` — so one
erases a rectangle to black and the other paints one white. That pair *is* the
animation:

```
for each star:
    PatBlt(hdc, oldX, oldY, size, size, BLACKNESS)   // rub out
    advance the star
    PatBlt(hdc, newX, newY, size, size, WHITENESS)   // draw it again
```

No frame buffer, no double buffering, no clearing the screen. Only the
handful of pixels that changed are ever touched, which is how this ran
comfortably on a 2003 machine.

And because `BLACKNESS` and `WHITENESS` ignore the brush entirely, the stars
need no color management at all.

### Why "no `SetPixel`" was the key observation

GDI can draw dots (`SetPixel`), lines (`LineTo`), images (`BitBlt`), curves,
text, polygons. `ssstars.scr` imports exactly three GDI functions:
`GetClipBox`, `PatBlt`, `GetStockObject`.

A Windows program must name every system function it uses (see §9), so the
import list is a complete inventory of its capabilities. Three entries with
`PatBlt` among them and `SetPixel` absent leaves exactly one possibility:
**the stars are filled rectangles**. That conclusion came before reading any
drawing code, and it is what makes the macOS port draw hard-edged squares with
antialiasing switched off.

---

## 6. Coordinates run downward

GDI puts the origin at the **top-left** corner, with **y increasing
downward** — the scanline order of a CRT.

This is the opposite of the mathematical convention, and the opposite of what
macOS does by default. It is the one genuine reversal between the two
platforms, and the reason the port's drawing code contains
`height - y - side`.

---

## 7. Why every function name ends in `W`

The imports are `CreateWindowExW`, `GetMessageW`, `DefWindowProcW` — not
`CreateWindowEx`. Windows NT is internally Unicode (UTF-16), but had to
support older programs written for 8-bit character sets. So most APIs
taking text exist twice:

- `...A` — ANSI, 8-bit characters
- `...W` — wide, UTF-16

`CreateWindowEx` is a macro selecting one at compile time. The `W` suffixes
throughout `ssstars.scr` mean it was compiled as a Unicode program, which is
also why its embedded strings are UTF-16 — the detail that made plain
`strings` come up empty in `TEARDOWN.md` §2.

---

## 8. Resources, dialogs, and settings

### Resources

A Windows EXE carries a read-only **resource section** (`.rsrc`) holding
non-code data: icons, string tables, version info, and dialog templates. It is
compiled from a text `.rc` file and linked in.

This is why `ssstars.scr` can report its own name and version without those
strings appearing in the code, and it is where "Starfield Simulation",
"Number of stars (10-200)", and `5.00.2195.6601` were found.

### Dialogs

A dialog is not built by creating controls one at a time. It is a **template**
in the resource section — a list of control types, IDs, and pixel positions —
handed to the system:

```c
DialogBoxParamW(hInstance, templateId, parent, dlgProc, 0);
```

Windows creates the controls and runs the dialog. Your dialog procedure is
another message `switch`, and control interactions arrive as `WM_COMMAND`
messages carrying the control's numeric ID.

The setup dialog uses a **spin control** (the little up/down arrow pair) for
density — its window class `fmsctls_updown32` appears in the strings — and a
scroll bar for warp speed, which is why `SetScrollRange` and `SetScrollPos`
are imported. Those two imports are what corrected my initial misreading of
warp speed as a checkbox, in `TEARDOWN.md` §8: checkboxes do not have ranges.

### Settings: INI files and the registry

Before the registry, Windows configuration lived in `.ini` text files:

```ini
[Screen Saver.Stars]
Density=25
WarpSpeed=5
```

The API reads them by key, with a default value baked into the call:

```c
GetPrivateProfileIntW(L"Screen Saver.Stars", L"Density", 25, L"control.ini");
```

Windows 2000 had the registry and the saver uses it too — the imports include
`RegOpenKeyW` and `RegQueryValueExW`, and `Control Panel\Desktop` is in the
strings, which is where the system stores which saver is active and whether a
password is required. But the saver's *own* two settings stayed in
`control.ini`, a Windows 3.1 file, in 2003. That is backward compatibility
doing what it does.

---

## 9. How a program finds `PatBlt`: the import table

This is the mechanism that made the teardown tractable, so it is worth
understanding properly.

`PatBlt` lives in `GDI32.DLL`, at an address not known until the moment the
program runs. So the compiler cannot emit a direct call. Instead:

1. The EXE contains an **import table**: a list of DLL names, each with a list
   of function names it needs.
2. It also reserves an array of empty pointer slots — the **Import Address
   Table** (IAT).
3. At load time, Windows opens each DLL, looks up each name, and writes the
   real address into the corresponding IAT slot.
4. Calls compile to an **indirect** call through the slot:
   `call dword ptr [0x0100101c]`.

Three consequences matter.

**A stripped binary still names every borrowed function.** Symbols for the
program's *own* functions can be discarded, but imports cannot — the loader
needs them. That is free, reliable information in an otherwise anonymous
binary.

**The import list bounds what the program can possibly do.** Hence §5: three
GDI entries is a complete graphics inventory.

**Each import has a fixed, unique address.** `PatBlt`'s slot is `0x0100101c`
and nothing else uses it. So finding every drawing call in 18 KB of anonymous
machine code is one grep:

```
$ grep '100101c' dis.txt
 10016fa:  calll  *0x100101c
 10017f7:  calll  *0x100101c
```

Two hits — the erase and the draw. No need to read the program in order, and
no need for symbols.

---

## 10. Reading a call: `stdcall`

One last piece of Win32 convention explains how the arguments were recovered.

Win32 uses the **`stdcall`** calling convention:

- arguments are pushed onto the stack **right to left**, so the *last* thing
  pushed is the *first* argument;
- the called function cleans up the stack itself.

So this sequence:

```asm
pushl $0x42          ; rop      <- pushed first = LAST argument
...
pushl %eax           ; h
pushl %eax           ; w
pushl %edi           ; y
pushl %ecx           ; x
pushl -0x8(%ebp)     ; hdc      <- pushed last = FIRST argument
calll *0x100101c     ; PatBlt
```

reads, in source order, as:

```c
PatBlt(hdc, x, y, w, h, BLACKNESS);
```

Matching that against the documented signature identifies every register:
`%ecx` holds the screen x, `%edi` the screen y, `%eax` the star's size — used
for both width and height, so the stars are squares — and `0x42` says this
call erases. The registers were nameless; the calling convention plus the
function prototype named them.

---

## 11. What makes a `.scr` a screen saver

Almost nothing. A `.scr` **is** an ordinary Windows EXE with a different
extension. Windows finds them by scanning for that extension and runs them
with a command-line flag:

| Flag | Meaning |
|---|---|
| `/s` | run full screen |
| `/c` | show the settings dialog |
| `/p <hwnd>` | draw the small preview into the given window |

So `main` inspects its arguments and picks one of three behaviors. There was a
helper library (`SCRNSAVE.LIB`) that handled the boilerplate and called your
`ScreenSaverProc` instead, but the contract is just "an EXE that understands
three flags".

The password check was a separate concern: the imports include
`VerifyScreenSavePwd`, loaded from `PASSWORD.CPL` — a Windows 9x-era mechanism
where the saver itself asked whether the user could unlock. Windows 2000's
real security did not depend on it, but the code path survived.

---

## 12. The original, assembled from all of the above

Everything now has a name:

1. `main` sees `/s` and decides to run full screen.
2. `RegisterClassW` registers `WindowsScreenSaverClass`, naming the window
   procedure. `CreateWindowExW` makes a full-screen window.
3. `GetPrivateProfileIntW` reads `Density` (default 25, clamped 10–200) and
   `WarpSpeed` (default 5, clamped 0–10) from `control.ini`.
4. `WM_CREATE` arrives; `SetTimer(hwnd, 1, 50, NULL)` starts a 20 Hz tick.
5. `WM_SIZE` arrives; the handler stores the screen dimensions and the center
   point, then seeds every star.
6. The message loop runs. Every 50 ms a `WM_TIMER` message arrives and lands
   in the fourth branch of the `switch` from §2.
7. That branch calls `GetDC`, then for each star: `PatBlt(..., BLACKNESS)` to
   erase, integer math to advance it, `PatBlt(..., WHITENESS)` to redraw.
   Then `ReleaseDC` and a `PeekMessage` to drop piled-up timer ticks.
8. Any keystroke or mouse movement posts `WM_DESTROY`, `PostQuitMessage` ends
   the loop, and the process exits.

That is the entire program. The parts the port reproduces — the projection,
the sizes, the speed ramp, the respawn rule, the random number generator —
all live inside step 7.

---

## 13. So what does the macOS port actually change?

With the Win32 side visible, the mapping table at the end of
`HOW-IT-WORKS.md` should now read as a list of things the port **does not
have to do**:

- no entry point, no `/s` `/c` `/p` — the system loads a class by name
- no `RegisterClassW`, no `CreateWindowExW` — the host owns the window
- no message loop, no `switch`, no `DefWindowProc` — you override methods
- no `SetTimer`, no `WM_TIMER` — you set an interval property
- no `GetDC`/`ReleaseDC` — a context is handed to you before drawing
- no raster operation codes — you set a fill color

What survives untouched is step 7's arithmetic: `x * 2560 / z + centerX`, the
truncating divide, `(2560 - z) / 640 + 1`, the `(warp + 1) * 10` speed target,
and the `seed * 0x343FD + 0x269EC3` generator.

Two platforms, thirty years apart, and the only thing worth carrying across
was about forty lines of integer math.
