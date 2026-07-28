# Greenacre Eagles Visual UX Skill

Use this skill for any visual, responsive, layout, accessibility or user-experience work on the Greenacre Eagles FC website.

## Purpose

Improve the existing site without redesigning it.

Preserve:

- current Greenacre Eagles branding;
- existing colour palette;
- existing typography;
- existing component system;
- current page structure unless a layout is clearly broken;
- existing functionality;
- current content unless wording is genuinely causing a usability issue.

The site should feel clean, modern, consistent, restrained and appropriate for a real football club.

Do not add generic AI-style marketing copy.

## Core design principles

Every visual change must improve at least one of:

- readability;
- hierarchy;
- consistency;
- responsiveness;
- accessibility;
- touch usability;
- navigation;
- spacing;
- content density;
- visual balance.

Do not change things only for decoration.

Avoid:

- excessive gradients;
- large empty spaces;
- oversized cards;
- oversized headings;
- unnecessary shadows;
- heavy animations;
- random colours;
- inconsistent border radiuses;
- excessive uppercase text;
- overly promotional wording;
- decorative elements that cover content;
- fixed widths that break at intermediate screen sizes.

## Responsive requirements

The site must be reviewed at:

- 320px
- 360px
- 375px
- 390px
- 430px
- 768px
- 1024px
- 1280px
- 1440px
- 1920px

Do not only test mobile and desktop. Intermediate widths are important.

At every width verify:

- no horizontal scrolling;
- no clipped headings;
- no overlapping columns;
- no text hidden behind images;
- no buttons outside the viewport;
- no inaccessible admin actions;
- no cards wider than their container;
- no cropped navigation;
- no unreadable logo or supporting text;
- no content covered by fixed or sticky elements.

## Layout rules

Use reliable responsive layouts.

Prefer:

- `minmax(0, 1fr)` in grid columns;
- `min-width: 0` on flexible children;
- responsive grid and flex layouts;
- fluid widths;
- constrained maximum widths;
- consistent section containers;
- contained decorative elements;
- natural wrapping;
- mobile-first layout changes.

Avoid:

- unnecessary absolute positioning;
- large negative margins;
- fixed card heights;
- fixed content widths;
- viewport-dependent hacks;
- overlapping columns;
- text positioned over unpredictable imagery;
- `overflow-hidden` that clips important content.

Decorative shapes must remain behind content and inside their intended section.

## Typography

Use a consistent type hierarchy.

Check:

- heading size;
- line height;
- maximum text width;
- wrapping;
- letter spacing;
- uppercase usage;
- spacing above and below headings.

Large headings must not overpower the layout or collide with adjacent content.

Club names and long headings must remain fully visible.

Scale headings fluidly where useful, using restrained responsive sizing.

Do not make every heading oversized.

## Cards and tiles

Cards should be compact, consistent and easy to scan.

Review:

- padding;
- image ratio;
- heading size;
- text length;
- internal spacing;
- button placement;
- card height;
- hover behaviour;
- mobile stacking.

Avoid oversized tiles with large empty areas.

Cards in the same section should feel related, but do not force equal heights where it creates unnecessary blank space.

Images should have a deliberate aspect ratio and use suitable object positioning.

## Buttons and interactive states

Every button and link must be tested in these states:

- default;
- hover;
- focus-visible;
- active;
- disabled;
- loading.

Text and icons must remain visible in every state.

Do not allow:

- green text on green backgrounds;
- white text on white backgrounds;
- invisible borders;
- buttons changing size on hover;
- hover movement that shifts layout;
- important behaviour that only works with hover.

Touch targets should be approximately 44px where practical.

Buttons should use consistent height, padding, radius and icon spacing.

## Navigation and headers

Review all public, portal and admin headers.

Check:

- club name width;
- logo size;
- association text;
- navigation spacing;
- button size;
- intermediate desktop widths;
- tablet collapse point;
- mobile drawer behaviour;
- menu scrolling;
- active states.

The club name must never be clipped, truncated accidentally or pushed under navigation.

At narrower desktop widths, simplify or collapse navigation before the brand area becomes cramped.

Do not reduce the logo to an unreadable size.

## Admin portal

All admin functions must remain accessible on phones.

Check:

- page actions;
- create buttons;
- approve/reject actions;
- edit/delete actions;
- filters;
- tabs;
- pagination;
- form controls;
- tables;
- row actions;
- modal buttons;
- navigation.

Do not hide essential admin actions.

Desktop tables may become:

- horizontal scroll containers;
- responsive cards;
- condensed rows;
- action menus.

Choose the pattern that is easiest to use.

## Forms and modals

Forms should use one column on narrow screens unless two columns clearly fit.

Check:

- label spacing;
- helper text;
- validation messages;
- file uploads;
- dates;
- selects;
- long values;
- buttons;
- modal scrolling;
- keyboard overlap;
- safe-area spacing.

Modal headers and footers must remain reachable.

## Contrast and accessibility

Maintain readable contrast for:

- body text;
- buttons;
- links;
- badges;
- form inputs;
- placeholders;
- error states;
- success states;
- navigation;
- footer;
- card overlays.

Keep visible focus states.

Do not use colour as the only status indicator.

Respect `prefers-reduced-motion`.

## Content density

Keep pages concise and scannable.

Remove or reduce:

- excessive introductory paragraphs;
- repeated descriptions;
- duplicate CTAs;
- oversized empty states;
- unnecessary labels;
- redundant section headings.

Do not remove useful content or functionality.

## Footer

Keep the footer compact and readable.

Retain the discreet credit:

Website by Asaad El Musty

Link:

https://www.instagram.com/asaadelmusty/

Use:

- `target="_blank"`
- `rel="noopener noreferrer"`

The credit must remain visually secondary to club information.

## Visual review workflow

For every visual task:

1. Inspect shared components and global styles first.
2. Identify patterns causing repeated issues.
3. Fix shared primitives before page-specific overrides.
4. Review public pages.
5. Review portal pages.
6. Review admin pages.
7. Test all target widths.
8. Test hover, focus and touch states.
9. Run automated checks.
10. Report every important issue found and fixed.

Do not stop after fixing the examples supplied by the user.

Treat screenshots as examples of broader patterns.

## Testing

Run available commands:

- npm run build
- npm run typecheck
- npm run lint
- npm test
- git diff --check

Where Playwright or browser tooling exists, use it to review representative pages at all target widths.

Take before-and-after screenshots where practical.

## Completion standard

The task is complete only when:

- no content is clipped;
- no important elements overlap;
- headings fit;
- navigation remains usable;
- card sizing is consistent;
- buttons remain readable;
- phone users can access all controls;
- intermediate screen sizes work;
- desktop design remains recognisably the same;
- automated checks pass.

Do not commit or push until all checks pass.