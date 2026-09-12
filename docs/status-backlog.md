# Status backlog — the set spell cards will use

Recorded 2026-09-11, from the developer's own list. **This is the canonical
set.** Anything a mockup, inspector or card draft shows that is not on this
list is invented, and anything here that a status inspector omits is missing.

Milestone 6 built the engine (`StatusService`, `StatusDefinitions`,
`EffectPrimitives`) but only enough statuses to prove it worked. This file is
the list of what the card library actually needs, and what each one still
costs.

Adding a status is normally **one entry in `StatusDefinitions` plus the cards
that apply it** — no service changes, because StatusService dispatches whatever
it finds. The exception is a status whose timing hook nothing fires yet: the
hook name exists in `Enums.TimingHook`, but until some service calls
`RunHook` at that moment, a definition hanging off it is dead code. Those are
marked **needs a dispatch site** below, and that is the real work in them.

| # | Status | Today | Remaining |
|---|--------|-------|-----------|
| 1 | Haste / slow (movement) | **Done** | — |
| 2 | Poison / regen (health) | Half | Regen |
| 3 | Strength up / down | Half | Down, and a persistent form |
| 4 | Immobilised — cannot move | **Done**, under another name | Rename decision |
| 5 | Silenced — cannot cast | Missing | Needs a dispatch site |
| 6 | Debt | **Done**, not as a status | Decide whether to surface it |
| 7 | Invulnerable / shielded | Missing | Needs a dispatch site |

---

## 1. Haste / slow — movement

**Done.** `Haste` and `Slow` in `StatusDefinitions`, both on `ModifyRoll` at
priority 0, both `RefreshDuration` so a second cast extends rather than
stacking. They sit after `ForcedRoll` (−100) and before `RollClamp` (+1000) by
construction, so a haste adds on top of a forced value and the clamp still
bounds the result.

Nothing to build. Cards that apply them: **Overclock** (id 26) hastes the
caster. No slow card exists yet — the definition is there and unused.

## 2. Poison / regen — health

**Half.** `Poison` exists: ticks on `TurnEnd` for the creature's owner, floors
at 1 so it cannot kill on its own, and damages through
`BattleService.DamageDefender` so the board repaints. Card: **Corroded Tape**
(id 24).

**Regen does not exist.** It is close to a mirror of Poison — heal on `TurnEnd`
instead of damage — but it needs two things Poison did not:

- A **cap at max HP**. Poison floors at 1; regen has to ceiling at
  `BaseMHP + BonusMHP`, or it turns into unbounded HP growth on any creature
  left alone. `BattleService` already tracks those separately for exactly this
  reason.
- A **heal counterpart to `DamageDefender`**, for the same reason that one
  exists: the board repaints on a signal, and a status writing `CurrentHP`
  directly is invisible to every display.

⚠ **Name collision.** There is already a `Regenerate` *keyword* on card data
(Grid Phoenix, id 8) that restores HP at battle end. That is a battle-local
keyword, not a status with a duration. Two different mechanics must not share a
name — pick `Regen` for the status or rename the keyword, but decide before
either ships.

## 3. Strength up / down

**Half.** Two things exist, and neither is quite this:

- `AttackBoost` — `BeforeBattleStats`, **attacker only**, and **consumed** by
  the battle it applies to. This is Signal Boost (id 5): a one-shot.
- `GlobalAttackShift` — `BeforeBattleStats`, every creature, lasts a round.
  Signal Flood (id 27).

**Missing: an ordinary, persistent strength modifier.** Up *and* down, applying
whether the creature attacks or defends, expiring on a duration rather than on
use. That is the version a spell card most often wants, and it is a plain
`StatusDefinitions` entry — `BeforeBattleStats` is already dispatched for both
combatants, so this one is free.

Open question worth settling with the card list: does a strength status attach
to the **player** (as `AttackBoost` does, so it follows whatever they fight
with) or to the **creature on a territory** (so it stays with the creature and
is lost when the creature is)? The engine supports both; they play very
differently.

## 4. Immobilised — cannot move

**Done, under a different name.** `Paralysis` returns `false` from `BeforeRoll`,
`MovementService.CanRoll` consults it, and the turn ends without the token
moving. Live-verified. Card: **Dead Air** (id 25).

The only thing to decide is **naming**. "Paralysis" is a flavour word;
"Immobilised" is what it does. Either is fine, but the kind name is what a
status inspector shows and what every future card references, so changing it
later is a rename across CardData, StatusDefinitions and any saved match log.

**Recommendation: rename to `Immobilised`.** It sits alongside `Silenced` as a
matched pair of plain-English restrictions, and "paralysis" would be the only
medical-sounding name in the set.

## 5. Silenced — cannot cast

**Missing, and needs a dispatch site.**

`Enums.TimingHook.BeforeSpell` exists and **nothing calls it**. The definition
itself is trivial — return `false`, the same shape as `Paralysis` on
`BeforeRoll` — but it does nothing until the cast path asks.

Work:

1. `CardEffectService.CanPlay` (or the `CastSpell` intent handler in
   `Main.server.lua`, next to the `CanRoll` check) folds through `BeforeSpell`
   and refuses with a real `RejectReason` when it comes back false.
2. `ActionValidator` should also drop `CastSpell` from `LegalIntents` while
   silenced, so the button dims instead of offering something the server will
   refuse. The brief's rule is that the buttons a client offers and the requests
   the server accepts cannot drift.

Note the interaction: `SpellChoice` now **stops** and waits. A silenced player
must still be able to reach `SkipSpell`, or being silenced softlocks their turn.

## 6. Debt

**Already designed, and deliberately not a status.** It lives in
`EconomyService` (`_debts`, `GetDebt`, `RequirePayment`), created when a toll
cannot be paid, repaid out of liquidation proceeds, and it is what makes a
player with debt and no land bankrupt. Milestone 5.

**Do not reimplement it as a status.** It is a persistent economic fact with its
own repayment rules, not a timed modifier, and moving it would put one
mechanic in two places.

What is worth doing is **surfacing it in the same list** — a status inspector
that shows Poison and Haste but not Debt is hiding the most consequential
condition a player can be in. Read-only view, mechanic stays in EconomyService.

## 7. Invulnerable / shielded

**Missing, and needs a dispatch site.**

`Enums.TimingHook.OnDamage` exists and **nothing calls it**. `BattleService`
computes and applies damage directly inside `runExchange`.

These are two different mechanics that belong together:

- **Invulnerable** — incoming damage becomes 0, for a duration. A fold that
  returns 0.
- **Shielded** — absorbs a *pool* of damage, then expires. The status carries a
  remaining amount, subtracts from it, passes the overflow through, and removes
  itself when empty. Priority matters: a shield must run **before** anything
  that scales damage, or it absorbs a number that later effects change.

Work: `BattleService.resolveStrike` folds the damage figure through `OnDamage`
before applying it, with a context naming striker, target and whether it is a
scroll. That function is already the single place damage is decided — critical
multiplier, then Neutralize/Reflect, then the pool — so the hook has an obvious
insertion point and only one of them.

Scrolls already bypass the land bonus and ordinary Neutralize/Reflect. Whether
they also bypass a shield is a **rule to confirm, not assume** — if uncertain,
it goes behind a `RulesConfig` flag with the uncertainty written down.

⚠ There are already battle keywords doing adjacent jobs — `Neutralize` reduces
qualifying damage to zero, `Reflect` returns it. Once `OnDamage` is dispatched,
those keywords should almost certainly be re-expressed as statuses applied at
battle start, the same way `AttackBoost` replaced the private `_attackBuffs`
table in M6. Otherwise there are two damage-modification systems running at once
with no defined order between them.

---

## Suggested order

1. **Strength up / down** — free, `BeforeBattleStats` is already dispatched.
2. **Regen** — one definition plus a heal counterpart to `DamageDefender`.
3. **Rename Paralysis → Immobilised** — cheap now, a migration later.
4. **Silenced** — first new dispatch site, and the smaller of the two.
5. **Invulnerable / shielded** — the largest, because `OnDamage` should
   probably absorb Neutralize and Reflect at the same time.
6. **Debt in the inspector** — presentation only, no rules change.

Item 5 is the one that is genuinely a design change rather than an addition, and
it should not be rushed in alongside the others.
