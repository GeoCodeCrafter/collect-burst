# progress

recorded in studio as i go, newest at the bottom

### 01 · first burst

click the rock and 14 bits of gold pop out, hang in the air for a moment, then turn into flat diamonds on the screen and curve into the counter. the counter goes up one per piece and does a little pop each time. rock comes back after a second

<img src="progress/01-first-burst.gif" width="720" alt="clicking the ore and the gold flying into the counter">

### 02 · heavier break

the rock shakes and swells for a split second and goes white before it pops, then there's a white puff where it was and the camera kicks. same burst as before but it feels like you actually hit something now

<img src="progress/02-heavier-break.gif" width="720" alt="the rock cracking, flashing white and bursting">

### 03 · drop, bounce, magnet

threw the explosion out, it wasn't satisfying. now the rock crumbles into rubble that tumbles and fades, the gold comes out as gems of 3 sizes that bounce on the ground, sit for a beat, then get pulled into you one after another with a trail. each one hops onto the screen and into the counter, which rolls up with a +30 under it. still placeholder cubes, real assets next

<img src="progress/03-drop-bounce-magnet.gif" width="720" alt="rock crumbling, gems bouncing and getting pulled into the player">

### 04 · real assets

swapped the cubes for proper models off the creator store. dark low poly rock with bits of ore in it, purple cut gems in 3 sizes, and the rubble is random rocks out of a 49 piece rock pack so no two breaks look the same. the counter icon and the bits flying into it are the actual gem now, rendered in 3D. store models come in at any size (the gem was 23 studs across) so everything gets scaled to fit. one free nugget model i tried had hidden scripts in it, so that one's gone

<img src="progress/04-real-assets.gif" width="720" alt="the ore rock crumbling and purple gems bouncing into the counter">

### 05 · scanned rock, real crystals

the store models looked cheap so i rebuilt everything. first try was a rock made from maths in blender and it looked like play dough in game. now the rock is a real photogrammetry scan (boulder 01 off poly haven, cc0) cut down to 16.5k tris with its scanned textures, and the amethyst is modelled from scratch: tapered six sided crystals with growth ridges and bevelled edges, a bed of little ones round the base, dark violet at the tips. gems sparkle when they land and bob while they wait. also fixed the whole rock being tipped 90 degrees, blender's Z-up leaves the pivot rotated when you import

<img src="progress/05-scanned-rock.gif" width="720" alt="the scanned rock with amethyst crystals breaking into gems">

### 06 · crystal cave

gave it a proper set to show it off: a cave carved out of terrain with a shaft in the roof, amethyst growing out of the walls and two lanterns either side of the rock. the drops are chunks of the rock's own amethyst now instead of a cartoon cut gem, and they don't turn into flat squares any more, the actual crystal flies up into the counter and shrinks into it. counter lost its box too, it's just the amethyst, a caption and the number. two bugs on the way: the rock landed on the cave roof because it looked for the ground from the sky, and no wall crystals showed up because terrain isn't solid for a moment after you make it

<img src="progress/06-crystal-cave.gif" width="720" alt="breaking the ore in the crystal cave, amethyst flying into the counter">
