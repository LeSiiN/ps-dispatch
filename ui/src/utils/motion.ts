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
} as const;

/** Entrances: decelerating, settles softly. */
export const EASE_IN = quintOut;
/** Exits and layout shifts: shorter tail, gets out of the way. */
export const EASE_OUT = cubicOut;

/**
 * Fly parameters for an alert card, derived from its screen anchor so it
 * always enters from the nearest edge instead of a fixed direction.
 */
export function alertFly(vPos: string, hPos: string) {
	const distance = 34;
	if (hPos === 'left') return { x: -distance, y: 0 };
	if (hPos === 'right') return { x: distance, y: 0 };
	return { x: 0, y: vPos === 'bottom' ? distance : -distance };
}
