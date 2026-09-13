# collect-burst

the "ore breaks and flies into your counter" effect for roblox. the rock crumbles, gems bounce out, get pulled into you and fly into the counter.

<img src="progress/03-drop-bounce-magnet.gif" width="720" alt="rock crumbling, gems bouncing and getting pulled into the player">

`rojo serve` or paste src/CollectBurst.luau into a ModuleScript in ReplicatedStorage and src/Demo.client.luau into a LocalScript in StarterPlayerScripts, then hit play and click the rock.

to use your own stuff make a folder `CollectBurstAssets` in ReplicatedStorage. everything's optional, missing ones fall back to placeholders:

- `Rock` model or meshpart
- `Gem` model or meshpart, about 1 stud, bigger gems are scaled up from it
- `Chunk` a meshpart for the rubble
- `Pickup` and `Break` sounds
- `Icon` a decal, used for the counter and the flying pieces

wip, see [PROGRESS.md](PROGRESS.md) for how it got here
