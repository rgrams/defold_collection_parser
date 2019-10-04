
Should be able to open pretty much any file Defold uses for collections, game objects, and components, they are all in the same format.

### Minimal usage examples:

__parser.decodeFile(file)__

```lua
file = io.open(path, "r")
local data = parser.decodeFile(file, filepath)
file:close()
```


__parser.encodeFile(file, data)__

```lua
local file = io.open(path, "w")
parser.encodeFile(file, data)
file:close()
```

