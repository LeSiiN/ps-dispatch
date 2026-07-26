<script>
  export let plate;
  export let index = null;   // GetVehicleNumberPlateTextIndex, 0-5

  // GTA's plate designs, by the index the native reports. Note the order is
  // not the intuitive one — Blue on White 2 is index 0, Blue on White 1 is 3:
  //   0 Blue on White 2 · 1 Yellow on Black · 2 Yellow on Blue
  //   3 Blue on White 1 · 4 Blue on White 3 · 5 North Yankton
  //
  // Four pieces of art cover six designs, so the white variants share. Which
  // of the two white pictures belongs to which white design can't be read off
  // the files, so if one comes out wrong in game, swap the two names here —
  // this table is the only place the mapping lives.
  const ART = {
    0: 'platewhite2',
    1: 'plateblack',
    2: 'plateblue',
    3: 'platewhite',
    4: 'platewhite',
    5: 'platewhite2',
  };

  // A plate whose design we don't know keeps the old neutral badge rather than
  // guessing: the MDT's plate checks, for one, only ever send characters.
  $: art = (index === null || index === undefined) ? null : ART[index];
</script>

{#if art}
  <!-- The image is set inline rather than in CSS: the NUI is served from
       html/, so the path has to stay relative to index.html, and a url() in
       the stylesheet gets rewritten at build time. -->
  <span class="pd-plateart pd-plateart--{art}" style="background-image:url('./plates/{art}.png')">{plate}</span>
{:else}
  <span class="pd-plate">{plate}</span>
{/if}
