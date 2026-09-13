# Common Holdings — UI Master Prompt

Paste everything below the line into Claude Design as a single brief. It is
written to be read cold, without this repo. Update it here when a decision
changes; this file is the source of truth for the brief, not the chat you
pasted it into.

Decisions this prompt encodes (settled 2026-09-11): neutral "Ninth Signal"
house style for all chrome; printed-and-industrial material language; lean
persistent HUD with full-focus takeovers; hybrid lobby (diegetic navigation,
overlay for data-heavy screens).

---

## ROLE

You are the lead UI/UX and visual designer for **Common Holdings**, a
Roblox board/card strategy game. Produce a complete, buildable interface
design system and the screens that use it — not mood boards, not
inspiration, not a style essay. Everything you draw has to survive being
rebuilt in Roblox's UI primitives by an engineer reading your annotations.

Two things matter more than anything else in this brief:

1. **It must not look like generated software.** See THE FAILURE MODE below.
   That section is not decoration; it is the acceptance criteria.
2. **It must serve a rules-heavy game.** Every panel exists because a
   specific decision or number needs to reach a player at a specific moment.
   A beautiful screen that hides the toll is a failed screen.

---

## THE GAME, ONLY AS IT AFFECTS UI

A Monopoly-meets-Magic hybrid in the lineage of Culdcept Saga. 2–4 players
("Cepters"), free-for-all or 2v2. Players roll dice, move around a board
graph, claim tiles by summoning creature cards onto them, and charge each
other tolls. You win by accumulating a target amount of wealth **and then
confirming it at a castle**.

The board is **3D geometry under a fixed, angled, turn-synced stage camera**.
Everyone in the match sees the same framing at the same time; the camera
snaps to whoever holds the turn. The UI is an overlay on that 3D view, so
the centre of the screen belongs to the board, not to you.

### Mechanical facts that constrain the design — honor all of them

- **Two separate currencies on screen at once.** *Current Magic (CM)* is
  spendable cash. *Total Magic (TM)* is CM + land value + symbols, and TM is
  what standings and victory read. Developing land **spends CM and raises
  TM** — cash goes down while score goes up. If the UI makes that read as a
  pure loss, the game's core strategic loop is invisible. These two numbers
  must never be confusable for each other.
- **One hand on screen at a time — the active player's.** Its owner sees the
  faces; every other player sees the *same number of card backs in the same
  place*. You never see your own cards on someone else's turn. Hand *size*
  is public; contents are private.
- **Entitlement is not always the turn holder.** When an invader commits an
  item, the **defender** chooses next. The visible hand follows whoever is
  currently entitled to decide, not whose turn it is.
- **Tiles have: owner, element, level 1–5, base value, land value, current
  toll, chain size, and a defending creature.** All of that is information a
  player will want before committing.
- **Chains are area-scoped** — same element, same owner, same area — and
  multiply toll value. A player needs to see their chains forming.
- **Battle is a nested sequence**: invasion begins, attacker commits an item
  (or declines), defender commits an item knowing what was committed (or
  declines), then it resolves. Attacker ST vs defender HP, where defender HP
  is `BaseMHP + BonusMHP` and the bonus (land bonus, armour) is recomputed
  fresh each battle and **absorbs damage first**. Speed classes rank First >
  Normal > Last; higher strikes first; the invader wins ties; a lethal first
  strike ends it. Keywords: First, Last, Critical, Penetration, Neutralize,
  Reflect, Regenerate, Support.
- **Declining is a real choice.** "No Item" and "Skip Spell" are buttons the
  player presses, not the absence of a press.
- **Junctions ask.** When movement reaches a branch the player picks an exit,
  with steps still remaining. A warp relocates **without consuming a step**.
- **An unaffordable toll liquidates, it does not refuse.** Available cash is
  taken, a debt is recorded, territories are sold off, and a player with debt
  and no land is bankrupt. This is a dramatic beat and needs real screen time.
- **Victory is two steps.** Hitting the TM goal is a *visible state you can
  lose again* — a rival taking your land can drop you back under the line.
  It is confirmed only by reaching a castle, where TM is re-checked. Arriving
  under the line wins nothing. The UI has to communicate "provisionally
  winning, not safe."
- **A lap** means collecting every required fort *type*, then the castle.
  Lap progress needs an indicator.
- **Statuses persist across turns**: Poison, Paralysis, Haste, Slow,
  RollClamp, ForcedRoll, AttackBoost, GlobalAttackShift. They have durations
  and a resolved priority order. A player must be able to answer "why was my
  roll a 6" after the fact — there is an append-only match log to surface.
- **Rejections carry a reason code** (wrong phase, not your turn, duplicate
  or stale request, can't afford). These need human sentences, not codes.
- A turn moves through named phases — turn start, draw, spell choice, roll,
  dice resolution, movement, landing resolution, landing action choice, turn
  end, victory check. The player should always know what the game is waiting
  for, in plain language. Never show internal phase names.

### Sample data to design against

Use these, not invented content. The card library is deliberately unfinished
and **you are not designing card content or balance numbers** — you are
designing the containers they arrive in.

Creatures, one per element: **Tape Gnome** (Earth), **Laser Salamander**
(Fire), **Phosphor Sylph** (Air), **Dewdrop Undine** (Water). Plus generic
spell and item cards. Make sample values look *played-in*, not tidy: a hand
of 6 with one unaffordable card, a board where one player is clearly ahead,
a toll of 137 rather than 150.

---

## SETTING AND THE FOUR ELEMENT SKINS

The game's identity is **retrofuturism** — futures that already happened —
published under the in-fiction studio banner **Ninth Signal**.

The four mechanical elements each wear one retrofuturist era as a *flavour
skin*. The element is the mechanic; the era is the costume:

| Element | Era skin | Flavour |
|---|---|---|
| **Fire** | Laser Grid | Glossy 1980s corporate future — neon grids, reflective glass, chrome airbrushing, robots, glass-block lobbies |
| **Air** | Early Cyber | Tron-grid, phosphor-green terminal, digital-frontier utopianism |
| **Earth** | Cassette Futurism | Beige plastic, tape reels, analog optimism (Nostromo-computer energy) |
| **Water** | Frutiger Aero | Glossy blue/green, translucent plastic, dew-drop nature-tech (mid-2000s "aqua") |

**Keep Y2K chrome and Frutiger Aero visually separate.** Y2K is
hard/silver/chrome; Frutiger Aero is glossy/translucent/organic. They blend
into each other if you are not deliberate.

### How the eras are allowed to appear — read this twice

**The four eras do not theme the interface.** They are card art, creature
flavour, tile identity, and at most an ink colour and a stamped glyph inside
an otherwise neutral frame. If Fire's neon starts recolouring panel chrome
while Earth's beige recolours it back, the UI becomes four inconsistent UIs
and the player relearns it every turn.

The one sanctioned exception: **full-screen takeover moments** (a summon, a
battle, a terraform) may lean into the relevant era as a set piece, inside
frames that still belong to the house style.

### The house style: Ninth Signal

All chrome — menus, HUD frames, buttons, lobby, panels — belongs to a fifth,
neutral identity: **Ninth Signal**, a plausible mid-1980s design-and-broadcast
house. Not any of the four eras. Think of it as the company that manufactured
the equipment the game is played on.

---

## MATERIAL LANGUAGE: PRINTED AND INDUSTRIAL

Everything in this interface is either **something printed** or **something
manufactured**. Nothing is "digital-looking" by default.

**Printed** means: flat spot inks on stock, halftone dots where a tone is
needed, visible registration that is very slightly off, knockout type, trim
marks, the kind of ink density variation a real press gives you. Paper and
card have a colour — warm off-white, newsprint grey, chipboard brown — not
`#FFFFFF`.

**Manufactured** means: injection-moulded plastic with draft angles and
parting lines, brushed and anodised aluminium, screen-printed legends on
bezels, recessed screens behind a lip, real fasteners, chamfers at edges,
rubber feet, label-maker tape. Matte. Surfaces have grain and wear.

**Light exists only where a real device would emit it**: an LED indicator, a
backlit legend pushbutton, a phosphor readout, a nixie or split-flap counter,
an EL panel. Everything else is lit *by the room*, not from within. Glow is a
scarce resource you spend on the one thing that matters most on a screen.

### Assign every panel a physical object

Before drawing a panel, decide what it *is* as a manufactured thing, and
annotate it. This is the single most effective defence against generic
output. Suggested vocabulary — use, adapt, or replace with better:

- Bottom HUD bar → a screen-printed equipment control panel / mixing desk strip
- Current Magic → a mechanical odometer or nixie readout, digits that roll
- Total Magic + goal → a linear VU-style meter with a printed scale and a
  physical goal marker you can see yourself under or over
- Toll amount → split-flap (Solari) board that clacks to the new number
- Phase / "what the game wants" → a row of illuminated legend pushbuttons,
  exactly one lit
- Turn order / standings → a slide-in card rack, one printed tab per player
- Cards in hand → actual printed cards with a bleed edge, rounded die-cut
  corners, a visible card back
- Battle takeover → a broadcast lower-third and scoreboard, as if the match
  is being televised
- Tile inspector → a printed property deed or spec sheet on a clipboard
- Liquidation → a bank ledger stamped in red, an actual rubber stamp mark
- Status effects → adhesive warning stickers applied to the player's tab
- Match log → continuous-feed tractor paper from a dot-matrix printer

Real-world design references to work from — study the actual objects, not
"retro" pastiches of them: Dieter Rams-era Braun; Technics and Sony hi-fi
faceplates; Interstate/Highway Gothic signage systems; Swiss and Japanese
poster grids; NASA "worm"-era print standards; arcade cabinet bezel and
control-panel screen printing; the Nostromo/Alien set computers; 1980s
console and boardgame manuals; Solari departure boards.

---

## THE FAILURE MODE — acceptance criteria, not suggestions

The brief is a failure if the result looks like every generated interface.
Concretely, **do not** produce any of the following:

**Surface and light**
- Purple-to-blue, or any hue-shifted, gradient backgrounds
- Frosted-glass / glassmorphism panels floating over a blur
- Soft outer glow on text, borders, or cards as a default treatment
- Drop shadows applied to everything to fake depth
- Bevel-and-emboss "shine" strips across the top of buttons
- Neon everywhere. Neon is a light source; a light source that is everywhere
  illuminates nothing

**Geometry**
- One corner radius applied to every element on the screen
- Rounded-everything. Some things are die-cut, some are milled square
- Panels that overlap, tangent, or intersect without a reason — boxes parked
  on top of other boxes. Every edge relationship is either a deliberate
  overlap with a shadow/notch that explains it, or a clean aligned gap
- Floating rectangles with no explanation of what holds them there
- Everything centred, everything symmetrical, no hierarchy

**Layout and content**
- Three evenly-spaced identical cards in a row as a layout solution
- Centred headline + subhead + two pill buttons as a screen
- Emoji as icons. Ever
- Icon-plus-label rows as the answer to every list
- Fake data that is suspiciously round and tidy
- No grid — just 16px of padding everywhere and hope

**A useful test:** could this panel be manufactured, photographed, and put in
a 1985 product catalogue? If it could only exist as a CSS file, redo it.

**A second test:** cover the text. Can you still tell which game this is, and
which panel you are looking at? If every panel becomes the same grey box,
there is no design here yet.

---

## DESIGN SYSTEM — deliver this before the screens

### Colour

Build a **shell palette** that owes nothing to the four elements: paper and
plastic neutrals (warm off-white, oatmeal, chipboard, cool grey), metal
tones, ink black, plus **one or two spot inks** that belong to Ninth Signal
and appear nowhere else in the game world. Spot inks carry alerts, the
active state, and the brand — they are not a background.

Then propose **final element inks**. The current values in code are greybox
placeholders and you should replace them:

```
Fire    = 255,  45, 185   (currently magenta — reads more Laser Grid than
                           Fire; propose a correction that still evokes
                           the era)
Air     =  60, 255, 130
Earth   = 196, 172, 130
Water   = 110, 210, 255
Neutral = 230, 225, 210
```

Element inks must survive **printed on the shell neutrals**, must be
distinguishable from each other at a 20px card pip, and must not vibrate
against each other when four players' tabs sit in a row.

**Never signal element by colour alone.** Design four **stamped glyphs**, one
per element — real marks, the kind that would be screen-printed on a panel —
carrying the same information in monochrome. Colourblind players and beige
tiles both depend on this.

Deliver the whole palette as **RGB triples in a table**, ready to drop into a
`Shared/UITheme` Lua module. Include every semantic role: surfaces, ink
levels, borders, disabled, danger/debt, affirmative, focus.

### Type

Choose a small, deliberate type system — a display/legend face and a
numeric/data face at minimum, with real size and weight steps. Numbers are
first-class in this game: currency, ST, HP, toll, level, dice. Treat the
numeric face as a design decision, not a fallback.

Roblox can load custom uploaded font faces, so name your ideal faces. Also
name a **built-in fallback** for each from what the engine ships, so the
first build is not blocked: Highway, Michroma, Jura, Sarpanch, Oswald, Code,
RobotoMono, GothamBlack, SourceSans.

Set a **minimum readable size for 10-foot console viewing** and state it.
Anything smaller than that minimum may not carry information a player needs
in order to act.

### Grid, spacing, depth

- A real baseline grid and spacing scale, stated in numbers, with the rule
  for when something is allowed to break it.
- A **depth model with exactly three or four layers** — board (3D), chassis,
  panel, overlay — and one consistent way each layer separates from the one
  beneath it. Is it a physical lip? A cast shadow? A scrim? Depth is a
  system, not per-element decoration.
- **Keep the centre of the screen clear.** The board lives there. Anchor
  persistent UI to edges and corners, and state the reserved board region.

### Components, with every state

Draw a component sheet. Every interactive component needs **default, hover,
pressed, disabled, and gamepad-focused** states, and the focused state has to
be visible from across a room. Minimum set:

Buttons (primary / secondary / destructive / decline), legend indicator, card
face (creature, spell, item), card back, card selected, card unaffordable,
player tab, numeric readout, meter with goal marker, tile chip, element
stamp, status sticker, toast and reject banner, modal scrim plus panel, list
row, tab bar, slider and stepper, tooltip, progress.

### Motion

Describe motion in mechanical terms and keep it short: split-flap flips,
relay clicks, a counter rolling, a panel sliding onto a detent, a stamp
coming down. **No floaty fades, no spring bounce, no drifting particles, no
sparkles.** Give durations in milliseconds and name the feel. Card deal and
battle resolution are the two places allowed real theatre.

---

## SCREENS TO DELIVER

Work in tiers. **Finish Tier 1 completely before starting Tier 2** — six
excellent screens beat twenty thin ones.

### Tier 1 — the game is unplayable without these

1. **Match HUD, your turn** — 4-player state. Persistent set only: whose turn
   it is, what the game is waiting for, your CM and TM against the goal, the
   four player tabs, your hand row, and the legal actions right now.
2. **Match HUD, not your turn** — the same frame, hand row showing backs,
   actions unavailable. Prove the two states differ at a glance.
3. **Card anatomy sheet** — creature face (name, element stamp, cost, ST, HP,
   speed class, keyword badges, art window), spell face, item face with
   category, card back, plus selected and unaffordable states. Define the art
   window's aspect ratio so real card art can be commissioned to it.
4. **Battle takeover** — the full sequence as separate frames: invasion
   begins, attacker item choice including No Item, defender item choice
   showing what the attacker committed, then resolution. Show ST against
   BaseMHP + BonusMHP with the land bonus called out as temporary, the strike
   order that speed class produces, and keyword badges in play.
5. **Tile inspector and development panel** — owner, element, level 1 to 5,
   base value, land value, current toll, chain size, defending creature. Then
   the development decision: cost in CM, toll before and after, and the TM
   delta, so spending cash to gain score reads as a gain.
6. **Landing decision** — pay toll, challenge, or summon, with the numbers
   each choice turns on.
7. **Lobby hub** — the 3D space and how a player understands where to go.
8. **Book builder** — 50-card deck construction against a growing collection:
   filter by element, type and cost, deck validity, curve, and a card list at
   a size where 50 entries are genuinely manageable.

### Tier 2

9. Standings and TM breakdown (CM + land + symbols) against the goal line
10. Goal-reached state and the castle confirmation moment, including losing
    the state when a rival takes your land
11. Liquidation, debt and bankruptcy
12. Junction route choice, overlaid on the 3D board
13. Terraform panel — choose target element, show cost and consequence
14. Spell choice, including Decline
15. Status effects on players and creatures, with durations
16. Lap progress — fort types collected, castle remaining
17. Match end and results
18. Reject toast — four real examples written as human sentences
19. Match log viewer
20. The dice roll moment

### Tier 3 — lobby and front end

21. Title and boot screen
22. Queue station: ranked or casual, FFA or 2v2, private server
23. Matchmaking and queue state, including cancelling
24. Collection and card unlock — unlocks are earned by winning, never bought
25. Cosmetics shop — cosmetic only, no pay-to-win, including Cepter token
    skins
26. Profile, rank and stats
27. Settings
28. Party and friends
29. Campaign station — a locked, clearly "not yet" fixture in the world

---

## THE LOBBY — hybrid diegetic

The lobby is a walkable 3D space. **Navigation is diegetic**: a player walks
up to a real object to make a choice — a cabinet to queue, a workbench to
edit their book, a shop counter, a locked door for campaign. Design the
approach affordance — how a player knows an object is interactive, and what
the prompt looks like — as a proper Tier 1 component.

**Data-heavy screens open as fullscreen UI.** A 50-card book does not belong
on a 3D prop. The transition from world to overlay is a designed moment: the
panel should feel like it came out of the object the player approached.

### 3D set-dressing standards

The same rules apply to geometry, and this is where blocky, clipped,
generated-looking scenes usually come from:

- **No primitives interpenetrating without intent.** Where two parts meet,
  design the joint: a trim piece, a reveal gap, a chamfer, a visible seam.
- **No z-fighting.** Coplanar faces are separated or merged, never left
  overlapping.
- **Real thickness.** Panels, counters and signage have depth. Nothing is an
  infinitely thin plane standing on its edge.
- **Consistent scale, stated in units.** Furniture, doors and signage are
  sized to the player. Nothing floats without visible support.
- **Edges are chamfered or filleted.** Perfectly sharp 90-degree edges on
  every object is the tell.
- **Wear where hands go** — worn counter edges, scuffed floor at doorways,
  fingerprints on a screen bezel.
- Light the room with practical sources that exist as objects inside it.

Deliver the lobby as an annotated layout plan plus at least one framed view
showing how the space reads on arrival.

---

## TECHNICAL CONSTRAINTS — this gets built in Roblox

Design freely, but annotate anything needing a special build. Real engine
limits the design has to respect:

- **Corner radius is uniform per frame.** Roblox UICorner applies one radius
  to all four corners. Per-corner radii need a 9-slice image or stacked
  frames — if you want them, say so explicitly.
- **Strokes are uniform.** UIStroke has one thickness on all sides. Per-side
  rules need thin frames instead. Annotate which you mean.
- **Linear gradients only.** UIGradient does linear colour and transparency
  ramps with rotation. There are no radial gradients.
- **No blur and no CSS-style box shadows.** There is no backdrop blur for UI.
  Every shadow or glow has to be authored as a 9-slice image asset — mark
  each one you use so it gets made.
- **Rich text spans exist** (bold, italic, colour, size, stroke). Use them for
  inline emphasis instead of splitting a label into many objects.
- Layout is anchor plus scale/offset with list and grid layouts and
  aspect/size constraints. Text scaling exists. Design on a real grid so this
  maps cleanly.
- Rotation on UI works but complicates clipping and hit detection. Sparingly.

**Resolutions and input.** PC and console are the primary target; mobile is
secondary but must work.

- Lay out at **1920x1080**, then prove the design again at **1280x720** and on
  a **phone**. Density that only works at 1080p is not finished.
- **TV overscan**: keep anything critical inside roughly a 5 percent safe
  inset.
- **Roblox reserves the top of the screen** for its own top bar and menu
  button. Leave the top-left and top-centre strip clear.
- **Gamepad**: the whole game must be playable without a cursor. Give every
  screen an explicit focus order and an unmistakable focus state.
- **Touch**: 44px minimum targets, controls within thumb reach, and the hand
  row usable one-handed.

---

## WHAT TO DELIVER

On one canvas, in this order:

1. **Token sheet** — palette as RGB triples with semantic roles, type scale,
   spacing scale, radii, depth layers, motion durations. Built to be
   transcribed straight into a Lua theme module.
2. **Element sheet** — the four inks, the four stamped glyphs, and a
   monochrome proof that they still read without colour.
3. **Component sheet** — every component, every state, gamepad focus included.
4. **Tier 1 screens** at 1920x1080, with the 3D board visible beneath, so the
   overlay is judged in context rather than on a flat backdrop.
5. **Density proofs** — one Tier 1 screen redrawn at 1280x720 and on a phone.
6. **Tier 2 and Tier 3** as far as they get.

Annotate every screen with: what physical object each panel is, which data
field each number comes from, and any build note from the constraints above.

**Label honestly.** Mark anything invented to fill a gap as placeholder. Card
content, balance numbers and the final card library are genuinely undecided
in this project, and a confident-looking invented number can be mistaken for
a decision. Where you had to guess, say what would settle it.

Before calling it done, re-read THE FAILURE MODE and check your own work
against it, item by item.
