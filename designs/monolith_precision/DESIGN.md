# Design System Documentation: Obsidian Editorial

## 1. Overview & Creative North Star
**Creative North Star: The Obsidian Architect**
This design system moves beyond the "generic dark mode" template. It is built on the principles of **Obsidian Editorial**: a philosophy that treats digital interfaces as high-end print medium. We are not just building an AI app; we are building a laboratory for the mind.

The goal is to move away from "contained" UI (boxes inside boxes) and toward "structural" UI. We achieve this through intentional asymmetry, extreme typographic contrast, and a sophisticated layering of dark-neutral tones that mimic the depth of volcanic glass. The experience should feel whispered, not shouted—authoritative, precise, and breathing with immense negative space.

---

### 2. Colors & Tonal Depth
The palette is rooted in a monochromatic spectrum, designed to minimize cognitive load while maximizing perceived depth.

| Token | Hex | Role |
| :--- | :--- | :--- |
| `background` | `#131313` | The base canvas. Dark, but not true black. |
| `primary` | `#FFFFFF` | Actionable items and high-impact text. |
| `on_primary` | `#1A1C1C` | Inverted text for primary buttons. |
| `surface_container_lowest` | `#0E0E0E` | Inset elements, deep wells, or inactive inputs. |
| `surface_container_high` | `#2A2A2A` | Elevated cards or focused modal layers. |
| `outline_variant` | `#474747` | Subtle structural definition (use sparingly). |

#### The "No-Line" Rule
Standard 1px solid borders are strictly prohibited for sectioning. To define a new area, use a background color shift. For example, a `surface_container_low` side-panel sitting against a `surface` background. The eye should perceive the edge through the change in tone, not a drawn line.

#### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers.
- **Base Level:** `background`
- **Sectioning:** `surface_container_low`
- **Interactive Elements:** `surface_container_high`
- **Floating Modals:** `surface_bright` with a 24px backdrop blur.

#### Signature Textures (The Director’s Polish)
While the base is minimalist, use a subtle 1% noise texture or a microscopic tonal gradient (e.g., `primary` to `primary_container` across 120 degrees) on primary CTAs. This prevents the "flat digital" look and adds a "physical" soul to the white elements.

---

### 3. Typography
We utilize **Geist Sans** for its Swiss-inspired neutrality and **Geist Mono** for technical/AI data.

*   **Display (Editorial Voice):** Use `display-lg` (3.5rem) with `-0.04em` letter spacing for hero headers. This creates a tight, "locked-in" editorial feel.
*   **Body (The Workhorse):** `body-md` (0.875rem) is the default for AI-generated responses. It provides high legibility without overcrowding the screen.
*   **Labels (The Technical Layer):** Use `label-sm` (0.6875rem) in **Geist Mono** for metadata (tokens, server latency, model IDs). All labels should be Uppercase with `0.05em` tracking to distinguish them from content.

---

### 4. Elevation & Depth
In this design system, height is an illusion created by light, not lines.

*   **The Layering Principle:** Depth is achieved by "stacking." A `surface_container_lowest` card placed inside a `surface_container_high` section creates a natural "carved out" effect. 
*   **Ambient Shadows:** For floating elements (menus/modals), use a "Whisper Shadow."
    *   *Shadow:* `0px 10px 40px rgba(0, 0, 0, 0.4)`
    *   The shadow color must be a tinted version of the background, never pure black.
*   **The "Ghost Border" Fallback:** If a border is required for accessibility, use the `outline_variant` token at **15% opacity**. It should be felt, not seen.
*   **Glassmorphism:** Use `surface_bright` at 60% opacity with a `20px` backdrop blur for floating navigation bars to allow the underlying AI "stream" of text to bleed through.

---

### 5. Components

#### Buttons
- **Primary:** `primary` background, `on_primary` text. No border. Corners: `6px`.
- **Secondary:** `surface_container_highest` background. Corners: `6px`.
- **Ghost:** No background. `primary` text. Hover state shifts background to `surface_container_low`.

#### Input Fields
Forbid the "boxed" input. Use a "Platform" style: A `surface_container_lowest` background with a subtle 1px bottom-stroke using `outline_variant`. On focus, the bottom stroke becomes `primary`.

#### Cards & Lists
Cards must never have dividers. Separate list items using `spacing-4` (1rem) of vertical white space. To group items, wrap them in a `surface_container_low` container with a `md` (0.75rem) corner radius.

#### AI Command Bar (The "Core" Component)
This is a floating bar using `surface_container_highest`. 
- **Radius:** `full` (9999px).
- **Style:** Glassmorphism (blur: 16px).
- **Leading Icon:** Lucide `Sparkles` in `primary`.

---

### 6. Do’s and Don’ts

#### Do
- **Embrace Asymmetry:** Align headings to the far left and metadata to the far right to create a wide, expansive feel.
- **Use Mono for Values:** Any number or technical ID must be in **Geist Mono**.
- **Generous Whitespace:** If you think there is enough space, add 20% more. This system thrives on "the void."

#### Don’t
- **Don't use #000000:** It kills the "Obsidian" depth. Stick to the `#0E0E0E` to `#131313` range.
- **Don't use Dividers:** If you need a divider, use a `1px` height `surface_container_low` block that only spans 80% of the container width.
- **Don't use Rounded-None:** Always keep corners between `6dp` and `12dp` (except for the Command Bar) to soften the brutalist typography.
- **Don't use colorful Icons:** Keep all Lucide icons in `on_surface_variant` (#C6C6C6) or `primary`.

---

### 7. Spacing Scale Reference
Use these tokens to maintain the editorial rhythm:
- **Tight (2):** 0.5rem (Icon/Text spacing)
- **Standard (4):** 1rem (Internal padding)
- **Section (8):** 2rem (Between content blocks)
- **Breathing (12):** 3rem (Margin from screen edges)