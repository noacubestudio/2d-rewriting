Early work-in-progress, better documentation and examples will be added later.

## Get started

Install LÖVE, download the folder and [launch the project](https://love2d.org/wiki/Getting_Started).
It should open two windows:

1. A console which logs basic info during run
2. The application window


### Loading

Download the files in the `example` folder of this repo:

| File              | Purpose                                      |
|-------------------|----------------------------------------------|
| `source.png`      | Initial board state as black & white pixels. |
| `rules.png`       | The rewriting rules used each step           |
| `symbols.png`     | The symbol patterns (see below)              |

### Basic Controls

* The arrow keys provide input while
* The space toggles bar toggles pause
* The `R` key reloads the intial state
* The escape key quits

Controls are listed in greater depth in the [Controls](#controls) section below.

## Usage

![grafik](https://github.com/user-attachments/assets/77a7406a-f3ed-44d9-8f4a-26c5661a3fcb)

### Initial Board State

The initial board state will be loaded from `source.png`.

The image should contain only grayscale pixels (zero saturaion / chroma):

* Black or white pixels are read as their literal value
* Grays will be converted to either black or white with a 50-50 chance

### Rules

The rules are parsed from `rules.png`.

Each rule replaces the pattern on the left with the one on the right as follows:

1. Pixels with any color saturation (chroma) are ignored and can be used as comments
2. Patterns of black and white pixels are used to search the board and replace them
3. Gray pixels are wildcards
4. Rules with multiple options on the right will be chosen from at random
5. Gaps of one or more pixels separate rules and can be of any width

#### Advanced Rules

To combine multiple rewrites in a single rule (where all have to match), one way would be to make their dimensions distinct.
Images in the row that are not the same dimensions as the ones to the left and right of them are not rewrites, but keywords that modify the remaining rule (or are used while the rules run). If the image does not match a keyword, it is simply removed. This is why you can use a single black or white pixel to separate multiple rewrite rules that are, say, all 5x5 px patterns.

### Symbols

The graphics for each "keyword" below will be loaded from `symbols.png`, starting from the top of the image. The keywords will be loaded in descending order as shown below:

| Keyword         | Action                                          |
|-----------------|-------------------------------------------------|
| rotate          | Create all 4 rotations for the rest of the rule |
| flip horizontal | Creates both versions                           |
| flip vertical   | Creates both versions                           |
| Lock to grid    | *Currently not supported*                       |
| input right     | Matches user input of the right arrow           |
| input down      | Matches user input of the down arrow            |
| input left      | Matches user input of the left arrow            |
| input up        | Matches user input of the up arrow              |

It is useful to make the input symbols rotated versions of each other since a rotate keyword in front then rotates them in the rule before they are parsed.
This alos applies to the horizontal and vertical flip symbols. If you don't want a keyword to mess with another, make the latter entirely symmetrical. A more elaborate system with more control may be added later...

## Controls

### Basics

| Action     | Mouse / Key        | Details                                                  |
|------------|--------------------|----------------------------------------------------------|
| Quit       | Escape key         | Quit the application                                     |
| Pause      | Space bar          | Pause or unpause the update loop                         |
| Input      | Arrow keys         | Rules with matching input keywords will match for 1 turn |

### Programs & Boards

| Action     | Mouse / Key        | Details                                                                      |
|------------|--------------------|------------------------------------------------------------------------------|
| Load       | `L` Key            | Load the board data from disk                                                |
| Draw       | Left / Right Mouse | Click to draw single pixels, drag for rectangles.                            |
| Reset      | `R` Key            | Reset the image in the project folder                                        |
| Save       | `S` Key            | Save the board to the LÖVE [appdata folder][][^1] (overwrites existing file) | 

### Views & Visualization

| Action        | Mouse / Key        | Details                                        |
|---------------|--------------------|------------------------------------------------|
| Zoom          | Mouse wheel        | Changes the pixel and Window size              |
| Cycle view    | `Tab` key          | Toggle between viewing rules and the board[^2] |
| Visualization | `1` / `2`          | Decrement / increment heatmap visualizations   |

#### Heatmap Visualizations

The heatmap visualizations wrap around at the start / end.

* All heatmap visualizations other than the last show rewrites using each rule since last player input
* The last shows where rules apply in real-time. 

[^1]: The appdata folder also contains a settings.lua. Toggle the `logRules` setting if you want to see how rules are parsed in the console. It uses `$$` for white, `[]` for black, `..` for wildcard and single `;` to separate rewrites in the same rule.

[^2]: The rules view is currently incomplete and will be interactive later.

[appdata folder]: https://love2d.org/wiki/love.filesystem

![grafik](https://github.com/user-attachments/assets/b9c231ca-5ae1-436c-ac75-494c693f0f8c)

