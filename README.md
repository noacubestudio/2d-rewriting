Early work-in-progress, better documentation and examples will be added later.

## Get started
Install LÖVE, download the folder and [launch the project](https://love2d.org/wiki/Getting_Started).
It should open with a console that gives some basic feedback. Put a source.png, rules.png, and symbols.png in the same folder.

## Draw to describe
![grafik](https://github.com/user-attachments/assets/77a7406a-f3ed-44d9-8f4a-26c5661a3fcb)

The starting board is generated from source.png. It should contain black and white pixels. Gray will turn into either black or white with a 50-50 chance.

The rules are parsed from rules.png.

In rules, colors with any amount of chroma are ignored and can be used as comments. Patterns of white and black pixels will be searched for in the board and replaced. Gray pixels are wildcards.
Put multiple rectangular same-dimension b/w images side by side to create a rewrite rule that replaces the left with right. Multiple options on the right will be chosen from at random.

A row of fully ignored pixels (such as any saturated color) indicates the end of one rule and the start of another. Gaps can be any width. 

To combine multiple rewrites in a single rule (where all have to match), one way would be to make their dimensions distinct.
Images in the row that are not the same dimensions as the ones to the left and right of them are not rewrites, but keywords that modify the remaining rule (or are used while the rules run). If the image does not match a keyword, it is simply removed. THis is why you can use a single black or white pixel to separate multiple rewrite rules that are, say, all 5x5 px patterns.

The graphics for keyword graphics can be set by drawing them, one under the other, in symbols.png. The symbols correspond to the following keywords, in the same order:
* rotate  (creates all 4 rotations for the rest of the rule)
* flip horizontal (creates both versions)
* flip vertical (creates both versions)
* lock to grid (currently *not supported*)
* input right
* input down
* input left
* input up

It is useful to make the input symbols rotated versions of each other, since a rotate keyword in front then rotates them in the rule before they are even parsed.
Same with the horizontal and vertical flip. If you don't want a keyword to mess with another, make the latter entirely symmetrical. A more elaborate system with more control may be added later...

## Controls

Left and right mouse buttons can be used to draw rectangles of either color on the board, or to create single pixels.

`S` to save the current board to the LÖVE appdata folder as an image. Overwrites the previous image of the same name there. 

The appdata folder also contains a settings.lua. Toggle the `logRules` setting if you want to see how rules are parsed in the console. It uses $$ for white, [] for black, .. for wildcard and single ; to separate rewrites in the same rule.

`R` to reset to the image in the project folder.
Focusing the tab after making changes to the images elsewhere (or pressing `l`) should reload them if they changed.

`Arrow keys` to provide input. Rules with the matching input keyword will be able to match for one turn.

`Space` to pause the update loop.

Mouse wheel to change the pixel size/ window size. `Esc` to close program.

`TAB` to toggle betveen viewing the rules and the state of the board. The rules view is incomplete and will be interactive later.

`1`/`2` to cycle through heatmap vizualisations (decrement/ increment). The last visualization (wrap around to it by pressing 1) should show where rules apply in realtime.
The others show all rewrites using one rule (expanded, so just one rotation etc. individually) since the last player input.
