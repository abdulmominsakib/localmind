---
name: cue-animations
description: 'Flutter animation using the Cue package. Use for: adding animations, transitions, motion, enter/exit effects, hover effects, scroll animations, toggle animations, page transitions, draggable scrubbing, modal transitions, animated widgets, keyframe animations, spring physics, fade, slide, scale, rotate, blur, clip, decorate, parallax, stagger, delay, CueMotion presets. DO NOT USE FOR: non-animation UI work, state management, or layout without motion.'
---

# Cue Animation Skill
<!-- skill-version: 3 -->

## Core Mental Model

Cue separates animation into four concerns:

| Piece | Role |
|-------|------|
| `Cue` | **When** to animate (the trigger) |
| `Actor` | **What** is animated (wraps the child) |
| `Act` | **Which property** changes (fade, slide, scale, etc.) |
| `CueMotion` | **How** it moves (spring preset or timed curve) |

## General Flutter Conventions (Always Apply)

- **Always create `Widget` classes, never helper functions that return widgets.** Use `StatelessWidget` or `StatefulWidget` for any reusable or extracted UI — not `Widget _buildFoo()` methods or top-level functions.
- **Use shorthand constructors everywhere**, not fully qualified class constructors:

```dart
// Padding / EdgeInsets
.all(16)              not EdgeInsets.all(16)
.only(top: 8)         not EdgeInsets.only(top: 8)
.symmetric(h: 16)     not EdgeInsets.symmetric(horizontal: 16)
.fromLTRB(...)        not EdgeInsets.fromLTRB(...)

// BorderRadius
.circular(12)         not BorderRadius.circular(12)
.vertical(top: .circular(16))   not BorderRadius.vertical(...)

// Alignment
.topLeft / .center / .bottomRight   not Alignment.topLeft

// MainAxisAlignment / CrossAxisAlignment / MainAxisSize
.center / .spaceBetween / .min      not MainAxisAlignment.center

// BoxFit / Clip / TextOverflow
.cover / .antiAlias / .fade         not BoxFit.cover

// Colors
Colors.transparent / Colors.white   (unchanged — no shorthand available)
```

## Step-by-Step Procedure

1. **Pick the trigger** — choose the right `Cue` factory for the use case.
2. **Set the motion** — always provide `motion:` on `Cue` (or on `Actor`/`Act` for overrides).
3. **Wrap children in `Actor`** — or use `Cue(acts: [...])` for a single child.
4. **Choose acts** — use shorthand factories (`.fadeIn()`, `.slideY()`, `.scale()`, etc.).
5. **Add stagger if needed** — use `delay:` on `Actor` to offset multiple children.

## Trigger Reference

```dart
// One-shot entrance when widget mounts
// Supports: repeat, reverseOnRepeat, repeatCount, onEnd
Cue.onMount(
  motion: .smooth(),
  repeat: false,               // loop the animation
  reverseOnRepeat: false,      // ping-pong when looping
  repeatCount: 3,              // finite loop count (null = infinite)
  onEnd: (forward) { ... },   // fires on completion in either direction
  acts: [...],
  child: child,
)

// Toggled by a boolean — forward on true, reverse on false
Cue.onToggle(toggled: isExpanded, motion: .smooth(), child: child)

// Restarts forward every time value changes
Cue.onChange(value: currentTab, motion: .smooth(), fromCurrentValue: true, child: child)

// Driven by pointer hover
Cue.onHover(motion: .interactive(), child: child)

// Driven by focus
Cue.onFocus(motion: .smooth(), child: child)

// Scrubbed continuously as the widget travels through the viewport (parallax-style).
// Progress = 0 when leading edge enters bottom of viewport, 1 when it reaches the top.
// Prefer non-overshoot motions (.smooth, .linear, .easeOut) — springs with bounce
// look jarring when scrubbed.
Cue.onScroll(child: child)

// Plays once when widget scrolls into view; stays complete. Does NOT reverse on scroll-out.
// Until revealed it scrubs like onScroll; once visible it plays forward with its motion.
// Use enabled: false to skip the animation and jump to completed state.
Cue.onScrollVisible(enabled: true, child: child)

// Scrubbed by external progress (e.g. drag)
Cue.onProgress(progress: dragNotifier, child: child)

// Index-based (page carousels, staggered lists)
// Works with CuePageController, CueTabController, CueIndexController
Cue.indexed(controller: cuePageController, index: index, child: child)

// Fully imperative
Cue(controller: myController, child: child)
```

**`debugLabel`** — add a label to any `Cue` to identify it in the DevTools scrubber:
```dart
Cue.onMount(motion: .smooth(), debugLabel: 'HeroCard', child: child)
```

## Actor and Acts

```dart
// Multiple acts, same child — compose freely
Actor(
  delay: 60.ms,
  acts: [
    .fadeIn(),
    .slideY(from: 0.15),
    .scale(from: 0.96),
  ],
  child: child,
)

// Extension shorthand for single child — skips explicit Actor
child.act([.fadeIn(), .slideUp()])

// Inline inside Cue (single animated child)
Cue.onMount(
  motion: .smooth(),
  acts: [.fadeIn(), .slideY(from: 0.2)],
  child: child,
)
```

**Act defaults — only set what differs from identity:**
Every act defaults both `from` and `to` to the resting/identity value for that property. You only provide the parameter that deviates. Common identity defaults:

| Act | `from` default | `to` default |
|-----|---------------|-------------|
| `scale` | `1.0` | `1.0` |
| `opacity` | `1.0` | `1.0` |
| `slideX/Y/Up/Down` | `0.0` | `0.0` |
| `blur` | `0.0` | `0.0` |
| `padding` | `EdgeInsets.zero` | `EdgeInsets.zero` |
| `rotate` | `0.0` | `0.0` |
| `translate` | `Offset.zero` | `Offset.zero` |

```dart
.scale(from: 0.9)       // → 1.0 (identity)
.scale(to: 1.05)        // from 1.0 (identity) →
.slideY(from: 0.15)     // → 0.0 (identity)
.blur(from: 8)          // → 0.0 (identity, i.e. sharp)
.padding(to: .symmetric(vertical: 12))  // from zero →
```

**Actor rules:**
- `Actor` without an ancestor `Cue` throws.
- Only one act per act key per `Actor` (no two slide variants in the same `Actor`).
- `motion` on an act > `Actor.motion` > `Cue` motion.
- `delay` is **additive**: `Actor.delay` + `Act.delay` stack — setting both does not override, it accumulates.

**One `Cue` per scene:** A single trigger should be covered by a single `Cue`. For a page entrance, use one `Cue.onMount` placed above all the `Actor`s — do **not** nest multiple `Cue.onMount` wrappers around individual children. Stagger via `Actor.delay`, not by multiplying triggers.

```dart
// CORRECT — one Cue coordinates the whole entrance
Cue.onMount(
  motion: .smooth(),
  child: Column(
    children: [
      Actor(acts: [.fadeIn(), .slideY(from: 0.12)], child: title),
      Actor(delay: 60.ms, acts: [.fadeIn(), .slideY(from: 0.12)], child: subtitle),
      Actor(delay: 120.ms, acts: [.fadeIn(), .slideY(from: 0.12)], child: button),
    ],
  ),
)

// WRONG — three separate triggers for the same scene
Cue.onMount(acts: [.fadeIn()], child: title)
Cue.onMount(acts: [.fadeIn()], child: subtitle)   // ✗
Cue.onMount(acts: [.fadeIn()], child: button)     // ✗
```

## Motion Hierarchy

Motion cascades down and can be overridden at each level:

```
Cue(motion: .smooth())          ← default for all Actors below
  Actor(motion: .gentle())      ← default for all acts on this Actor
    Act(motion: .snappy())      ← overrides for this specific act only
```

- `Cue.motion` is the scene-wide default.
- `Actor.motion` overrides `Cue.motion` for all acts on that `Actor`.
- An act-level `motion` overrides everything for that single property.
- You only need to set `motion` where behavior should differ from the parent.
- **Setting `motion` implicitly sets `reverseMotion` to the same value.** To make reverse feel different, set `reverseMotion` explicitly. This applies at both `Cue` and `Actor` level.

```dart
// reverse uses the same .smooth() motion — implicit
Cue.onToggle(toggled: isOpen, motion: .smooth(), child: child)

// reverse uses a different motion — explicit override
Cue.onToggle(toggled: isOpen, motion: .smooth(), reverseMotion: .snappy(), child: child)

// same rule on Actor
Actor(motion: .bouncy(), reverseMotion: .linear(160.ms), acts: [...], child: child)
```

```dart
Cue.onMount(
  motion: .smooth(),           // scene default
  child: Column(children: [
    Actor(
      acts: [.fadeIn(), .slideY(from: 0.15)],  // both use .smooth()
      child: title,
    ),
    Actor(
      motion: .gentle(),       // overrides .smooth() for this Actor
      acts: [
        .scale(from: 0.95),    // uses .gentle()
        .fadeIn(motion: .snappy()),  // overrides .gentle() for fadeIn only
      ],
      child: card,
    ),
  ]),
)
```

## Delay is Additive

`Actor.delay` and per-act `delay` stack — they do not override each other.

```dart
Actor(
  delay: 80.ms,              // Actor-level delay
  acts: [
    .fadeIn(),               // starts at 80 ms
    .slideY(from: 0.15, delay: 40.ms),  // starts at 80 + 40 = 120 ms
  ],
  child: child,
)
```

Use `Actor.delay` for gross stagger between children, and act-level `delay` for fine-grained sequencing within a single `Actor`.

## Motion Presets (CueMotion)

Prefer spring-based presets for natural interruption handling.

```dart
.smooth()       // fast, clean, no overshoot — best default
.snappy()       // near-instant micro-interactions
.bouncy()       // visible overshoot for emphasis
.gentle()       // slower, softer
.wobbly()       // exaggerated, playful
.interactive()  // responsive drag/hover feel
.spatial()      // layout movement
.effect()       // decorative property changes

// Fixed-duration timing when physics isn't appropriate
.linear(250.ms)
.easeIn(300.ms)
.easeOut(300.ms)
.easeInOut(300.ms)
.curved(400.ms, curve: Curves.easeInOut)

// Special variants
CueMotion.none          // zero-duration, resolves instantly — use when a CueMotion
                        // is required by the API but no animation is wanted
.threshold(200.ms, breakpoint: 0.5)
                        // stays at the start value, then snaps instantly to the end
                        // when progress crosses breakpoint (0→1 fraction).
                        // no interpolation — useful for visibility toggles that must
                        // align precisely with another ongoing animation.
```

## Act Families — Quick Reference

### Transform
```dart
.scale(from: 0.9)              // uniform scale
.zoomIn() / .zoomOut()
.rotate(to: 180)               // visual-only rotation in degrees (transform, no layout impact — prefer this)
.rotateLayout(to: 1, unit: .quarterTurns)  // rotates AND recomputes layout — use only when layout must shift
.rotate3D(to: Rotation3D(x: 15), perspective: 0.001)
.flipX() / .flipY()
.translate(to: Offset(0, 24))  // pixel translation
.translateX(from: -20) / .translateY(from: 20)
.translateFromGlobal(offset: rect.topLeft)   // translate from a global screen position
.translateFromGlobalRect(rect)               // translate from the center of a global rect
.translateFromGlobalKey(key)                 // translate from a widget identified by GlobalKey
.slide(from: Offset(0, 2))     // fractional offset (relative to widget size)
.slideX() / .slideY() / .slideUp() / .slideDown()
.slideFromLeading() / .slideFromTrailing()
.stretch(to: Stretch(x: 1.2, y: 0.8))       // scale axes independently
.skew(to: Skew(x: 0.3))                     // skew transformation
.transform(to: Matrix4.rotationZ(0.3))       // raw Matrix4 (from defaults to identity)
.parallax(slide: 0.3, axis: .horizontal)     // scrub-linked parallax slide
```

### Visual
```dart
.opacity(from: 0, to: 1)
.fadeIn() / .fadeOut()
.blur(from: 8) / .focus() / .unfocus()
.backdropBlur(to: 8)
.colorTint(from: Colors.white60, to: Colors.black)
```

### Layout & Clipping
```dart
// NSize constructors used by sizedClip and sizedBox:
// NSize(w: 200, h: 100)   — explicit width and height
// NSize.width(200)       — fixed width, height follows child
// NSize.height(100)      — fixed height, width follows child
// NSize.square(48)       — equal width and height
// NSize.size(Size(...))  — from a Size object
// NSize.childSize        — both axes follow child (no constraint)
// double.infinity → resolves to parent's max constraint

.sizedBox(width: .tween(40, double.infinity), height: .tween(40, 56))
.sizedClip(from: NSize.square(24), to: NSize.height(68))
.sizedClip(from: NSize.size(rect.size), to: NSize.width(240))
.fractionalSize(widthFactor: .tween(0.2, 1.0), heightFactor: .fixed(0.5))
.padding(to: .symmetric(vertical: 12))
.align(from: .bottomCenter, to: .bottomLeft)
.clipHeight(fromFactor: 0.3) / .clipWidth() / .clip() / .circularClip()
```

### Multi-Property Acts — AnimatableValue

Some acts animate multiple independent properties on the same widget. Each property accepts an `AnimatableValue`:
- `.tween(from, to)` — interpolates between two values
- `.fixed(value)` — constant, not animated (still required if the act needs to know the value)

Omitting a property entirely means that property is ignored/left at its natural value.

**`.sizedBox`** — animate width and/or height independently:
```dart
.sizedBox(
  width: .tween(80, double.infinity),  // expands to fill
  height: .fixed(40),                  // height stays constant
)
.sizedBox(width: .tween(100, 300))     // only width animates
```

**`.fractionalSize`** — size as a fraction of the parent (0.0–1.0):
```dart
.fractionalSize(
  widthFactor: .tween(0.2, 1.0),
  heightFactor: .fixed(0.5),
  alignment: .fixed(.center),
)
```

**`.decorate`** — animate box decoration properties individually.
Prefer `DecoratedBoxActor` for standalone use; use `.decorate` when composing with other acts inside an `Actor`:
```dart
.decorate(
  color: .tween(Colors.transparent, Colors.white),
  borderRadius: .tween(.circular(0), .circular(16)),
  border: .fixed(Border.all(color: Colors.blue)),
  boxShadow: .tween(
    [BoxShadow(blurRadius: 0)],
    [BoxShadow(blurRadius: 8, offset: Offset(0, 4))],
  ),
  gradient: .tween(fromGradient, toGradient),
)
```

**`CardAct` / `CardActor`** — animate card surface properties.
Prefer `CardActor` for standalone card animations; use `CardAct` inside `Actor(acts:[...])` when combining with other acts:
```dart
// Preferred for card-only animations
CardActor(
  elevation: .tween(1, 8),
  color: .tween(Colors.white, Colors.blue.shade50),
  borderRadius: .tween(.circular(8), .circular(24)),
  shadowColor: .fixed(Colors.black),
  margin: .tween(.zero, .all(8)),
  child: child,
)

// Inside an Actor alongside other acts
Actor(
  acts: [
    CardAct(elevation: .fixed(2), borderRadius: .tween(.circular(8), .circular(24))),
    .scale(from: 0.95),
  ],
  child: child,
)
```

**`PositionAct` / `PositionedActor`** — animate stack positioning.
Prefer `PositionedActor` — it reads naturally inside a `Stack`:
```dart
Stack(
  children: [
    PositionedActor(
      from: .fill(),                           // fills the stack
      to: .fromSTEB(20, 250, 20, 24),          // shrinks to specific insets
      child: myWidget,
    ),
    PositionedActor.keyframed(
      frames: .fractional([...]),
      relativeTo: stackSize,
      child: myWidget,
    ),
  ],
)
```

**`DecoratedBoxActor`** — standalone animated decoration, no `Actor`/`Cue` nesting needed:
```dart
DecoratedBoxActor(
  color: .tween(Colors.grey.shade100, Colors.blue.shade50),
  borderRadius: .tween(.circular(8), .circular(32)),
  shape: .circle,
  child: SizedBox.square(dimension: 48),
)
```

**`PaintActor`** — custom painting driven by animation progress:
```dart
PaintActor(
  painter: myCustomPainter,   // receives CueAnimation<double> to drive paint
  child: child,
)
```

### Specialized
```dart
// Animate along a custom Path — optional autoRotate to face direction of travel
PathMotionAct(
  path: myPath,          // a Path() with a single continuous metric
  autoRotate: true,      // rotate widget to face path direction
  alignment: .center,    // pivot/anchor point
)
```

### Style & Decoration
```dart
// textStyle — animates between two complete TextStyle values
.textStyle(
  from: TextStyle(fontSize: 14, color: Colors.grey),
  to: TextStyle(fontSize: 22, color: Colors.black, fontWeight: .bold),
)
// iconTheme — animates icon properties
.iconTheme(from: IconThemeData(size: 24), to: IconThemeData(size: 20))
```

### Positional (Stack)
See **Multi-Property Acts** section above for full `PositionedActor` coverage.

```dart
PositionedActor(from: .fill(), to: .fromSTEB(20, 250, 20, 24), child: child)
PositionedActor.keyframed(frames: .fractional([...]), relativeTo: size, child: child)
```

### Custom Value
```dart
// TweenActor — animate any value with a builder (does not need to be inside Actor)
TweenActor<double>(
  from: 0,
  to: 1,
  motion: .smooth(),
  builder: (context, animation) {
    return FadeTransition(opacity: animation, child: child);
  },
)
```

## Keyframes

### Motion-based (spring between values)
```dart
ScaleAct.keyframed(
  frames: Keyframes([
    .key(0.92),
    .key(1.06, motion: .bouncy()),
    .key(1.0),
  ], motion: .smooth()),
)
```

### Fractional (time-based at specific progress points)
```dart
TranslateAct.keyframed(
  frames: .fractional([
    .key(const Offset(0, 24), at: 0.0),
    .key(const Offset(0, -8), at: 0.7),
    .key(Offset.zero, at: 1.0),
  ], duration: 450.ms),
)

// ScaleAct with fractional keyframes (used for custom switch squish)
ScaleAct.keyframed(
  frames: .fractional([
    .key(1.1, at: 0.4),
    .key(1.1, at: 0.6),
    .key(1.0, at: 1.0),
  ]),
)
```

## Reverse Behavior

```dart
// Mirror: same animation plays in reverse
.fadeIn(reverse: .mirror(delay: 40.ms))

// To: reverse targets a different value
.scale(to: 1.06, reverse: .to(0.98))

// None: reverse does nothing
.zoomIn(reverse: .none())

// Different motion for forward vs reverse on Cue/Actor
Cue.onToggle(
  toggled: isOpen,
  motion: .smooth(),
  reverseMotion: .snappy(),
  child: child,
)

Actor(
  motion: .smooth(),
  reverseMotion: .linear(160.ms),
  delay: 80.ms,
  reverseDelay: 20.ms,
  acts: [...],
  child: child,
)
```

## Modal Transitions

### CueModalTransition

Morphs any trigger widget into a full modal. Captures the trigger's screen-space `Rect` and passes it to the builder so you can animate directly from the trigger's position and size.

```dart
CueModalTransition(
  motion: .smooth(),
  reverseMotion: .snappy(),        // defaults to motion if omitted
  alignment: .bottomRight,         // anchors modal's corner to trigger's same corner
                                   // null = no positioning, builder must place itself
  barrierColor: Colors.transparent, // use transparent for contextual menus
  barrierDismissible: true,
  hideTriggerOnTransition: true,   // hides trigger while modal is open (seamless morph)
  useRootNavigator: true,          // false = scoped to a nested Navigator
  backdrop: Actor(                 // optional: rendered behind modal, in front of barrier
    acts: [.backdropBlur(to: 8)],
    child: ColoredBox(color: Colors.transparent),
  ),
  triggerBuilder: (context, open) {
    return FloatingActionButton(onPressed: open, child: Icon(Icons.add));
  },
  builder: (context, rect) {
    // rect = trigger's bounding box in global screen coordinates
    return Actor(
      acts: [
        .sizedClip(from: NSize.size(rect.size), to: NSize.width(300)),  // expand from trigger size
        .translateFromGlobalRect(rect),   // move FROM trigger's position
      ],
      child: myModalContent,
    );
  },
)
```

**`alignment`:** controls which corner/point of the modal is anchored to the same point on the trigger.
- `.bottomRight` — ideal for FABs and corner action buttons that expand in-place
- `.center` — works well for inline buttons that expand in place
- `null` — no automatic positioning; builder output goes into a full-screen `Stack` and must position itself

**`rect` in builder** — common act patterns using the trigger rect:
```dart
.sizedClip(from: NSize.size(rect.size))          // expand from trigger's exact size
.translateFromGlobalRect(rect)                    // translate an element from trigger's center
.translateFromGlobal(offset: rect.topLeft)        // translate from trigger's top-left corner
.iconTheme(from: IconThemeData(size: rect.height * 0.5), to: IconThemeData(size: 20))
```

**Nesting** — bind different gestures to different modals from the same trigger:
```dart
CueModalTransition(
  motion: .smooth(),
  triggerBuilder: (_, openTap) {
    return CueModalTransition(
      motion: .smooth(),
      triggerBuilder: (context, openLongPress) {
        return GestureDetector(
          onTap: openTap,
          onLongPress: openLongPress,
          child: myButton,
        );
      },
      builder: (context, rect) => LongPressContent(rect: rect),
    );
  },
  builder: (context, rect) => TapContent(rect: rect),
)
```

**Close the modal** from inside the builder with `Navigator.of(context).pop()`.

### showCueDialog / CueDialogRoute

For standard dialogs driven by Cue. All `Actor`s inside automatically pick up the route controller via `CueScope` — no need to pass a controller explicitly.

```dart
showCueDialog(
  context: context,
  motion: .smooth(),
  reverseMotion: .snappy(),
  barrierColor: Colors.black54,
  builder: (context) => Actor(
    acts: [.fadeIn(), .slideY(from: 0.12)],
    child: AlertDialog(title: Text('Hello')),
  ),
)

// Or push directly for full control:
Navigator.of(context).push(
  CueDialogRoute(
    motion: .smooth(),
    reverseMotion: .snappy(),
    pageBuilder: (context, _, _) => MyModalContent(),
  ),
);
```

## CueDragScrubber

`CueDragScrubber` maps drag distance to animation progress. The controller is taken from the nearest `CueScope` ancestor automatically, or passed explicitly.

```dart
CueDragScrubber(
  distance: 250.0,          // pixels that map to full 0→1 progress travel
  axis: .vertical,          // .vertical (default) or .horizontal
  scrubDirection: .auto,    // .forward, .reverse, or .auto (infers from controller state)
  releaseMode: .fling,      // what happens on finger lift:
                            //   .fling  — flings with velocity, falls back to .snap
                            //   .snap   — snaps forward if progress > 0.5, else reverses
                            //   .none   — stays wherever drag stopped
  forceLinearScrubbing: true, // ignore motion curves while scrubbing (default: true)
  onAnimationEnd: (forward) { ... },  // fires when animation completes/dismisses
  child: myDraggableWidget,
)
```

**`scrubDirection`:**
- `.forward` — dragging in the positive axis direction increases progress (0→1)
- `.reverse` — dragging in the positive axis direction decreases progress (1→0)
- `.auto` — infers from controller state: completed/forward → reverse scrub; dismissed/reverse → forward scrub

**Snap-to-final pattern** — combine with `Cue.onToggle(onEnd:)` to let Cue own the snapping and state:

```dart
Cue.onToggle(
  toggled: _isDraggedDown,
  onEnd: (forward) => setState(() => _isDraggedDown = forward),
  motion: .smooth(),
  child: CueDragScrubber(
    distance: 250.0,
    releaseMode: .fling,
    child: myCard,
  ),
)
```

**Explicit controller** — skip `CueScope` when the scrubber is far from the `Cue` in the tree:

```dart
CueDragScrubber(
  controller: _myController,
  distance: 200.0,
  child: handle,
)
```

## Page/Index Controllers

| Controller | Use case |
|------------|----------|
| `CuePageController` | `PageView` — drop-in replacement for `PageController` |
| `CueTabController` | `TabBar` / `TabBarView` — drop-in for `TabController` |
| `CueIndexController` | Custom index-driven sequences (carousels, steppers) |

```dart
final controller = CuePageController(viewportFraction: 0.8);

PageView.builder(
  controller: controller,
  itemBuilder: (context, index) => Cue.indexed(
    controller: controller,
    index: index,
    // During drag: scrub mode (progress mapped directly, motion shapes curve)
    // After snap:  play mode (motion + Actor delays produce staggered entrance)
    child: Column(
      children: [
        Actor(acts: [.fadeIn(), .slideY(from: 0.12), .rotate(from: 4.5, reverse: .to(-4.5))], child: title),
        Actor(delay: 60.ms, acts: [.scale(from: 0.96), .fadeIn()], child: card),
      ],
    ),
  ),
)
```

## Imperative Controllers

Only reach for this when the trigger factories are insufficient.

```dart
late final CueController _controller;

@override
void initState() {
  super.initState();
  _controller = CueController(vsync: this, motion: .smooth());
}

@override
void dispose() {
  _controller.dispose();  // releases timeline; no need to release tracks manually
  super.dispose();
}

@override
Widget build(BuildContext context) {
  return Cue(
    controller: _controller,
    acts: [.fadeIn(), .slideY(from: 0.2)],
    child: child,
  );
}
```

For typed imperative animations outside widgets:
```dart
final opacity = controller.tweenTrack<double>(from: 0, to: 1);
final scale = controller.keyframedTrack<double>(
  frames: Keyframes([.key(0.92), .key(1.06), .key(1.0)], motion: .smooth()),
);
// Release when no longer needed (if controller stays alive):
opacity.release();
```

## Debug Tools

Wrap in `kDebugMode` to get a scrubber overlay for completed animations:

```dart
MaterialApp(
  builder: (context, child) {
    if (kDebugMode) return CueDebugTools(child: child!);
    return child!;
  },
)
```

## Style Rules (Always Follow)

- Use shorthand: `.smooth()` not `Spring.smooth()`, `.fadeIn()` not `Act.fadeIn()`
- Prefer `Cue(acts: [...])` over wrapping a single child in an explicit `Actor`
- Use `.act([...])` extension for single-widget inline cases
- One `Cue` per coordinated group — place it high enough to cover all related `Actor`s
- Compose multiple acts in one `Actor`; separate `Actor`s for different delay/motion groups
- Never `Actor` without a `Cue` ancestor

## Common Patterns by Use Case

| Use Case | Pattern |
|----------|---------|
| Entrance animation | `Cue.onMount` + `.fadeIn()`, `.slideY()`, `.scale()` |
| Expand/collapse | `Cue.onToggle` + `.clipHeight()`, `.fadeIn()`, `.rotate()` |
| Tab/selection highlight | `Cue.onToggle` + `.sizedClip()`, `.colorTint()` |
| Hover feedback | `Cue.onHover(motion: .interactive())` + `.scale(to: 1.03)` |
| Context menu | `CueModalTransition` + `.sizedClip()`, `.translateFromGlobalRect()` |
| Page carousel | `Cue.indexed` + `CuePageController` + `.parallax()`, `.rotate()` |
| Drag-to-dismiss | `CueDragScrubber` + `Cue.onToggle(onEnd:...)` |
| Scroll reveal | `Cue.onScrollVisible` + `.fadeIn()`, `.slideY()` |
| Loading → done morph | `Cue.onChange` + `.sizedClip()`, `.fadeIn()`, `.zoomIn()` |
| Custom value animation | `TweenActor<T>(from:, to:, builder:)` |
