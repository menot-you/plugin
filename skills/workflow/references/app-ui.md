# NOTT.app UI and UX rules

Read this file before a change to what NOTT.app draws. The builder (`nott:app`)
builds against it. The screen QA reader (`nott:qa`) checks screenshots of the
installed app against it. The design contract `docs/design/harness/DESIGN.md`
wins over this file. Use goose `ui/desktop/src` in the donor reference tree as the product
reference, and check each claim against that source.

Each rule has a check that a person can do on a screenshot or in the code. A
rule that you cannot check is not in this file.

## Owner rules

These rules come from the owner.

1. An icon control that opens a menu or a panel opens it on hover. A click and
   the keyboard also open it. Escape closes it. The pointer can move from the
   icon onto the panel and the panel stays open. The same component behaves the
   same in every window.
   Example: `HeaderMenu` (`NottKit/UI/Canvas/HeaderMenu.swift`) opens on hover,
   keeps a 250 ms grace for the pointer, and toggles on a click or a key.
   Source: WCAG 2.2 SC 1.4.13 (dismissible, hoverable, persistent),
   https://www.w3.org/TR/WCAG22/.
2. Each icon control shows a tooltip on hover. The tooltip names what the
   control does. It starts with a verb, uses sentence case, has no end period,
   does not repeat the control's name and has at most 60 characters. Use the
   same text for the accessibility label.
   Example: `GlassIconButton` (`NottKit/UI/Canvas/CanvasParts.swift`) sets
   `.help` and `.accessibilityLabel` from `label`. Its `label` is optional: an
   icon control with no `label` has no tooltip and no name, and that is a
   defect.
   Source: Apple HIG, Offering help,
   https://developer.apple.com/design/human-interface-guidelines/offering-help.
3. One component draws one kind of control, and one theme holds the shared
   constants. A view takes each size, gap, radius, color and duration from
   `NottKit/Theme`. A new number literal in a view is a defect.
   Example: today `GlassIconButton` (`Theme.barButton`, 24 pt) and
   `WorkspaceIconButton` (`NottKit/UI/Workspace/Shell/WorkspaceControl.swift`,
   `Theme.WorkspaceShell.barButton`, 30 pt) both draw an icon button. Do not add
   a third. A change that touches both moves them toward one.
   Source: WCAG 2.2 SC 3.2.4 (consistent identification). Also Dieter Rams, "nothing
   must be arbitrary", https://www.vitsoe.com/us/about/good-design.

## Hierarchy

The thing that needs the owner is the strongest mark on the screen. A failure
outranks it where both apply, and it shows its glyph or its words. Secondary text uses the secondary text token, not a smaller copy of the
primary style. Check: on the screenshot, the first element
that the eye finds is the one that the screen is for.
Example: a node that needs the owner shows the red dot. A failed node keeps its
own red (`statusError`) and its glyph (DESIGN.md, rule 2).
Source: Nielsen Norman Group heuristic 8, "every extra unit of information ...
competes with the relevant units",
https://www.nngroup.com/articles/ten-usability-heuristics/.

## Spacing rhythm and alignment

Space inside a group is smaller than space between groups. Siblings share one
edge or one baseline. Each value comes from a theme constant. Check: on the
screenshot, a text line, icon or shape that has no group, no container and no
alignment line with its neighbours is a stray element.
Example: in full screen, `CanvasTopBar.inset` puts the top row
`Theme.chromeInset` from the corner, the same inset that the foot has.
Source: Laws of UX, law of proximity and law of common region,
https://lawsofux.com/law-of-proximity/. Also the ui-ux-pro-max skill,
`~/.agents/skills/ui-ux-pro-max/references/pro-rules.md` (a 4/8 pt spacing rhythm).

## Affordance and feedback

A control looks like a control and changes on hover. A press shows a response
at once. An action that takes more than 400 ms shows progress and has a stop
control. A disabled control looks disabled.
Example: `HoverLift` (`NottKit/UI/Canvas/CanvasPolish.swift`) lifts a node 2 pt
under the pointer.
Source: Laws of UX, Doherty threshold, https://lawsofux.com/doherty-threshold/. Also
Nielsen Norman Group heuristic 1 (visibility of system status).

## Keyboard access

Each action has a keyboard path. Keyboard focus is visible and uses the
`focusRing` token. Escape closes the popover or menu that has focus. Do not give
a standard shortcut a new meaning (Command-comma opens Settings).
Example: the navigators on Command-1 to Command-5 and the Command-K palette
(DESIGN.md, rule 1).
Source: WCAG 2.2 SC 2.1.1 and SC 2.4.7. Also Apple HIG, Keyboards,
https://developer.apple.com/design/human-interface-guidelines/keyboards.

## Contrast and color

Text has a contrast of 4.5:1 or more, or 3:1 at 18 pt or more. An icon glyph, a
focus ring or a state mark has 3:1 or more against each opaque surface under
it. Color is never the only signal. Text is 10 pt or more. A control target is
20x20 pt or more (the macOS default is 28x28 pt). Both themes pass.
Example: the contract hues are marks only, never text (DESIGN.md, rule 2).
The tokens come from `docs/design/tokens.json`.
Source: WCAG 2.2 SC 1.4.3 and SC 1.4.11. Also Apple HIG, Accessibility,
https://developer.apple.com/design/human-interface-guidelines/accessibility.

## Motion that has a purpose

Motion answers an input of the owner (hover, drag, a press) or a real event,
runs once and ends. Under Reduce Motion, a change cross-fades or occurs at
once. A new repeating animation is a defect. DESIGN.md, rule 3, names two
exceptions: the hub's die while the core works, and the breath of the red dot
(`NeedsYouPulse`, `NottKit/UI/Canvas/CanvasPolish.swift`).
`NottKitTests/StillnessTests.swift` names each repeating producer that the owner
allows. Do not remove one, and do not add one that it does not name.
Example: `HoverLift` answers the pointer with one spring and lifts at once
under Reduce Motion. `HeaderMenu.animation` uses the theme fade under Reduce
Motion.
Source: Apple HIG, Motion,
https://developer.apple.com/design/human-interface-guidelines/motion. Also the impeccable skill,
`~/.agents/skills/impeccable/reference/craft-floor.md` (one authored moment, not scattered effects).

## Empty, loading and error states

Each list or panel has a loading state, an empty state and an error state, and
each state looks different. An empty state says what is missing and the one act
that fills it. An error says the problem and the recovery in plain words, with
no error code and no internal id.
Example: `EmptyCanvas` (`NottKit/UI/Canvas/CanvasParts.swift`) says "No nodes
yet" and "Send an intent to Guará to create your first node."
Source: Nielsen Norman Group heuristic 9. Also Apple HIG, Loading,
https://developer.apple.com/design/human-interface-guidelines/loading.

## Words

Use one word for one thing in all windows. A label uses the owner's words, not
internal jargon. A menu item uses title case, and it has an ellipsis when the
act asks for more input.
Example: `EmptyCanvas` says "No nodes yet" and "create your first node": the
same word for the same thing in both lines.
Source: Nielsen Norman Group heuristics 2 and 4. Also Apple HIG, Menus,
https://developer.apple.com/design/human-interface-guidelines/menus.
