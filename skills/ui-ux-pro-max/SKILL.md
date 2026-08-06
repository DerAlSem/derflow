---
name: ui-ux-pro-max
description: Design intelligence catalog for web and mobile — 50+ styles, 97 color palettes, 57 font pairings, 99 UX guidelines, 25 chart types across 9 stacks. Searchable Python database with priority-based recommendations. Use when choosing color palettes/typography, reviewing code for UX issues, building landing pages/dashboards, or implementing accessibility requirements. Triggers on "какие цвета выбрать", "шрифт под spa/wellness", "стиль для лендинга", "WCAG checklist".
license: MIT
compatibility: opencode
---

# UI/UX Pro Max — Design Intelligence

Comprehensive design guide for web and mobile applications. Searchable Python
database with priority-based recommendations.

## When to Apply

Reference these guidelines when:
- Designing new UI components or pages
- Choosing color palettes and typography
- Reviewing code for UX issues
- Building landing pages or dashboards
- Implementing accessibility requirements

## Rule Categories by Priority

| Priority | Category | Impact |
|---|---|---|
| 1 | Accessibility | CRITICAL |
| 2 | Touch & Interaction | CRITICAL |
| 3 | Performance | HIGH |
| 4 | Layout & Responsive | HIGH |
| 5 | Typography & Color | MEDIUM |
| 6 | Animation | MEDIUM |
| 7 | Style Selection | MEDIUM |
| 8 | Charts & Data | LOW |

## Quick Reference

### 1. Accessibility (CRITICAL)
- `color-contrast` — minimum 4.5:1 for normal text, 3:1 for large text and UI components
- `focus-states` — visible focus rings (≥2px, ≥3:1 contrast against adjacent colors)
- `alt-text` — descriptive, not "image of X"
- `aria-labels` — for icon-only buttons
- `keyboard-nav` — Tab order matches visual order
- `form-labels` — `<label for=>` linked to input

### 2. Touch & Interaction (CRITICAL)
- `touch-target-size` — minimum 44×44px (WCAG 2.2 SC 2.5.8 sets 24×24 minimum)
- `hover-vs-tap` — primary actions must work on click/tap (not hover-only)
- `loading-buttons` — disable during async; show spinner inside
- `error-feedback` — inline, near the field, not top-of-screen
- `cursor-pointer` — on every clickable element

### 3. Performance (HIGH)
- `image-optimization` — WebP/AVIF, srcset, `loading="lazy"` for below-fold
- `reduced-motion` — wrap all non-essential animation in `@media (prefers-reduced-motion: reduce)`
- `content-jumping` — reserve space for async content (`min-height`/`aspect-ratio`)

### 4. Layout & Responsive (HIGH)
- `viewport-meta` — `<meta name="viewport" content="width=device-width, initial-scale=1">`
- `readable-font-size` — 16px minimum body text on mobile
- `horizontal-scroll` — content fits viewport width
- `z-index-management` — define scale (10 modal, 20 dropdown, 50 toast)

### 5. Typography & Color (MEDIUM)
- `line-height` — 1.5–1.75 for body text
- `line-length` — 65–75 characters per line
- `font-pairing` — display + monospace, or serif + geometric sans

### 6. Animation (MEDIUM)
- `duration-timing` — 150–300ms for micro-interactions
- `transform-performance` — animate `transform`/`opacity`, never `width`/`height`
- `loading-states` — skeleton (shaped like content), not spinner

### 7. Style Selection (MEDIUM)
- `style-match` — match style to product type (no brutalism in healthcare, no glassmorphism in dense data)
- `consistency` — same style across all pages of one product
- `no-emoji-icons` — SVG icons (Heroicons / Lucide / Simple Icons), never 🎨🚀⚙️

### 8. Charts & Data (LOW)
- `chart-type` — match chart to data type (trend → line, comparison → bar, share → donut, geo → choropleth)
- `color-guidance` — ColorBrewer / Viridis / accessible palettes, never rainbow
- `data-table` — provide table alternative for accessibility

## How to Use

The catalog is queried via the included Python search script.

### Step 1: Analyze Requirements

Extract from the user's request:
- **Product type**: SaaS, e-commerce, portfolio, dashboard, landing page, etc.
- **Style keywords**: minimal, playful, professional, elegant, dark mode, etc.
- **Industry**: healthcare, fintech, gaming, education, etc.
- **Stack**: React, Vue, Next.js — default to `html-tailwind` if unspecified

### Step 2: Generate Design System (REQUIRED)

```bash
python3 ~/.config/opencode/skills/ui-ux-pro-max/scripts/search.py \
  "<product_type> <industry> <keywords>" \
  --design-system \
  -p "Project Name"
```

This searches 5 domains in parallel (product / style / color / landing / typography),
applies `ui-reasoning.csv` rules, returns: pattern, style, colors, typography, effects,
anti-patterns.

### Step 3: Supplement with Detail Queries

```bash
python3 ~/.config/opencode/skills/ui-ux-pro-max/scripts/search.py \
  "<keyword>" --domain <domain>
```

Domains: `product` · `style` · `typography` · `color` · `landing` · `chart` · `ux`

### Step 4: Stack Guidelines

```bash
python3 ~/.config/opencode/skills/ui-ux-pro-max/scripts/search.py \
  "<keyword>" --stack html-tailwind
```

Available stacks: `html-tailwind` (default), `react`, `nextjs`, `vue`, `svelte`,
`swiftui`, `react-native`, `flutter`, `shadcn`.

## Output Formats

- `--design-system -f markdown` for documentation, terminal output for chat

## Common Rules — frequently overlooked

### Icons & Visual Elements
| Rule | Do | Don't |
|---|---|---|
| No emoji icons | SVG (Heroicons / Lucide) | 🎨🚀⚙️ |
| Stable hover | color / opacity transition | scale that shifts layout |
| Correct brand logos | Simple Icons (verified) | guess paths |
| Consistent icon sizing | `w-6 h-6` on `viewBox=24 24` | mixed sizes |

### Interaction & Cursor
- `cursor-pointer` on all clickable cards
- Hover feedback (color, shadow, border) — instant visual
- Transitions `duration-200 ease-out` — not instant, not >500ms

### Light/Dark Mode Contrast
- Light text: `#0F172A` (slate-900); muted: `#475569` minimum (NOT gray-400)
- Glass card light: `bg-white/80` (NOT `bg-white/10` — invisible)
- Border visibility: `border-gray-200` (NOT `border-white/10` on white bg)

### Layout & Spacing
- Floating navbar: `top-4 left-4 right-4` — NOT `top-0 left-0`
- Content padding: account for fixed navbar height
- Max-width consistent: pick `max-w-6xl` or `max-w-7xl`, never mix

## Pre-Delivery Checklist

- [ ] No emoji as icons (SVG instead)
- [ ] All icons from one set (Heroicons / Lucide)
- [ ] Brand logos verified (Simple Icons)
- [ ] Hover states don't cause layout shift
- [ ] Theme colors used directly (`bg-primary`) — not `var(--primary)` wrappers in components
- [ ] All clickable elements have `cursor-pointer`
- [ ] Transitions 150–300ms
- [ ] Focus rings visible
- [ ] Light mode: 4.5:1 contrast minimum
- [ ] Glass/transparent visible in light mode
- [ ] Borders visible in both modes
- [ ] No horizontal scroll on mobile (test at 375px)
- [ ] All images have alt text
- [ ] Form inputs have labels
- [ ] Color is not sole indicator
- [ ] `prefers-reduced-motion` respected
- [ ] Tested at 375 / 768 / 1024 / 1440
