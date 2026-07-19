<script>
  // Map thumbnail centered on a call, cropped out of the ps-mdt map image —
  // no canvas, no network beyond the one NUI image CEF caches anyway.
  //
  // The world→image math is the MDT Map.svelte CRS verbatim: projected
  // pixel = (0.02072·x + 117.3, −0.0205·y + 172.8) · scale, and the image
  // spans pixels 0..1024 at Leaflet zoom 2 (scale 4). Dividing by 1024
  // yields the normalized 0..1 position on the (square) map image.
  //
  // Centering trick: the inner layer is ZOOM× the container width with the
  // map as its full background, anchored at the container center and shifted
  // by translate(-fx·100%, -fy·100%) — translate percentages refer to the
  // element's OWN size, so the call's map point lands exactly on the
  // container center regardless of container size. (Plain CSS
  // background-position percentages can't do this: they align image and
  // container at the SAME fractional point, which drifts off-center for
  // anything away from the map middle.)
  export let coords = null;      // { x, y } world coords
  export let priority = 2;       // 1 = red marker
  export let src = null;         // map image url (already probe-verified)
  export let height = 84;        // px

  // How much of the map the crop shows: the full image spans ~12,350 world
  // units, so ZOOM 14 ≈ an 880 m wide neighborhood view in a 320px thumb.
  const ZOOM = 14;

  $: fx = coords ? ((0.02072 * coords.x + 117.3) * 4) / 1024 : null;
  $: fy = coords ? ((-0.0205 * coords.y + 172.8) * 4) / 1024 : null;
  // Off-map calls (e.g. Cayo Perico) fall outside 0..1 → render nothing.
  $: valid = src && fx != null && fx >= 0 && fx <= 1 && fy >= 0 && fy <= 1;
</script>

{#if valid}
  <div class="pd-thumb" style="height:{height}px">
    <div
      class="pd-thumb-map"
      style="width:{ZOOM * 100}%; background-image:url('{src}'); transform:translate(-{fx * 100}%, -{fy * 100}%);"
    ></div>
    <div class="pd-thumb-marker {priority == 1 ? 'pd-thumb-marker--red' : ''}"></div>
  </div>
{/if}
