import { cubicOut, quintOut } from 'svelte/easing';

/**
 * One motion vocabulary for the whole UI.
 *
 * Everything that appears or disappears pulls its timing from here instead of
 * carrying its own hand-picked numbers, so the resource reads as one product
 * rather than a pile of independently animated widgets.
 *
 * Two rules behind the values:
 *  - Things LEAVE faster than they arrive. An exit is an acknowledgement, not
 *    a presentation, and a slow exit feels like lag.
 *  - Only `transform` and `opacity` are animated. Both are composited by the
 *    GPU, which matters in CEF where animating layout properties (width,
 *    height, top/left) on a dozen alert cards visibly stutters.
 */
export const DUR = {
	/** Micro feedback: badges, hints, hovers. */
	fast: 110,
	/** The default for panels, cards and modals. */
	base: 180,
	/** Reserved for the largest surfaces (the menu itself). */
	slow: 240,
	/** Exits, uniformly quicker than their entrance. */
	exit: 130,
	/** Alert cards get their own, more generous timing: they arrive
	 *  unannounced in the corner of the eye, so they need long enough to be
	 *  noticed as an event rather than registering as a flicker. */
	alertIn: 420,
	alertOut: 260,
} as const;

/** Entrances: decelerating, settles softly. */
export const EASE_IN = quintOut;
/** Exits and layout shifts: shorter tail, gets out of the way. */
export const EASE_OUT = cubicOut;

/** The screen edge an alert is anchored to, from its position string. */
export type Edge = 'left' | 'right' | 'top' | 'bottom';

export function edgeFor(vPos: string, hPos: string): Edge {
	if (hPos === 'left') return 'left';
	if (hPos === 'right') return 'right';
	return vPos === 'bottom' ? 'bottom' : 'top';
}

/**
 * The wipe always starts at the screen edge the alert is docked to, so the
 * card reads as coming IN from off-screen rather than materialising in place:
 * top-right opens right-to-left, top-center top-to-bottom, bottom-left
 * left-to-right, and so on.
 *
 * `inset(top right bottom left)` clips from each side, so revealing from a
 * given edge means shrinking the inset on the OPPOSITE side to zero.
 */
function wipe(edge: Edge, amount: number): string {
	const a = `${amount * 100}%`;
	if (edge === 'right') return `inset(0 0 0 ${a})`;
	if (edge === 'left') return `inset(0 ${a} 0 0)`;
	if (edge === 'bottom') return `inset(${a} 0 0 0)`;
	return `inset(0 0 ${a} 0)`;
}

/** Matching drift: the card slides in from the same edge it uncovers from. */
function drift(edge: Edge, distance: number): { x: number; y: number } {
	if (edge === 'left') return { x: -distance, y: 0 };
	if (edge === 'right') return { x: distance, y: 0 };
	if (edge === 'bottom') return { x: 0, y: distance };
	return { x: 0, y: -distance };
}

/** The squeeze on exit collapses toward the anchored edge, not the centre. */
function origin(edge: Edge): string {
	if (edge === 'left') return 'left center';
	if (edge === 'right') return 'right center';
	if (edge === 'bottom') return 'center bottom';
	return 'center top';
}

/**
 * Alert entrance — "signal acquired".
 *
 * The card drifts in from its anchored edge while a wipe uncovers it from
 * that same edge, so the motion has one consistent direction instead of
 * fighting itself. Opacity is front-loaded (t * 1.8, clamped) because the
 * wipe already hides the card; a second slow fade on top only read as sluggish.
 * Priority calls run ~15% shorter — urgency carried by motion, not just red.
 */
export function signalIn(
	node: Element,
	{ duration = DUR.alertIn, edge = 'right', priority = false }: SignalOpts = {},
) {
	const d = drift(edge, 44);
	return {
		duration: priority ? Math.round(duration * 0.85) : duration,
		easing: EASE_IN,
		css: (t: number, u: number) =>
			`transform: translate3d(${u * d.x}px, ${u * d.y}px, 0);` +
			`opacity: ${Math.min(1, t * 1.8)};` +
			`clip-path: ${wipe(edge, u)};`,
	};
}

/**
 * Alert exit — "signal lost".
 *
 * The wipe runs backwards, retracting the card into the edge it came from
 * while it squeezes very slightly toward that same side. Retracting rather
 * than sliding back out matters: sliding out the way it came in reads as
 * "undo", collapsing into the edge reads as "handled".
 */
export function signalOut(
	node: Element,
	{ duration = DUR.alertOut, edge = 'right' }: SignalOpts = {},
) {
	const d = drift(edge, 44);
	const horizontal = edge === 'left' || edge === 'right';
	return {
		duration,
		easing: EASE_OUT,
		css: (t: number, u: number) =>
			`transform: translate3d(${u * d.x * 0.3}px, ${u * d.y * 0.3}px, 0)` +
			` ${horizontal ? `scaleX(${1 - u * 0.05})` : `scaleY(${1 - u * 0.05})`};` +
			`transform-origin: ${origin(edge)};` +
			`opacity: ${t};` +
			`clip-path: ${wipe(edge, u)};`,
	};
}

interface SignalOpts {
	duration?: number;
	edge?: Edge;
	priority?: boolean;
}
