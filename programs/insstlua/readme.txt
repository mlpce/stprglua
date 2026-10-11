About insstlua

I wrote this program during development of gembindl. Although I'd written
unit tests while writing AES.LUA and VDI.LUA which tested various facets
of the binding in a more isolated way, I needed a more substantial program
which tested how the various parts worked together.

I needed to write a program which used the binding. I settled on a basic
set of requirements:

1) Have a menu bar
   -> to test menu resource, event loop, event handling, shortcuts
2) Non-modal dialogue boxes
   -> interaction with dialogue objects
   -> interaction events and resource data transfer
   -> rendering dialogues at different screen positions
3) Display information in windows
   -> window handling
   -> clipping
   -> vdi text display
   -> rectangle filling
   -> blitting and scrolling
4) Use modal dialogues
   -> alerts
   -> file selector
5) Use a coroutine to actually *do* something

Coroutines I'd not tested at all even after writing tosbindl, so this was
an important part of the requirement. I decided to write an installer. The
coroutine could be used to copy the actual data.

Most of the gembindl/utility directory was written during the
implementation of this program: a basic framework to allow me to run an
application, register with the AES, display a menu, keep track of windows
and display modeless dialogue boxes and windows containing text.

As an actual program, insstlua is not very useful. If someone is going to
install the Lua programs and gembindl, it's much easier just to copy files
with the GEM desktop. The value of insstlua was in its writing, the
process of testing AES.LUA, VDI.LUA and the creation of a general set of
utilities. The code of insstlua demonstrates one way of using gembindl.
For this reason, I decided to upload the source code.

Some points of note:

1) A Lua program Loads much faster if it (and gembindl) has been
precompiled to Lua byte code.
2) The program uses less memory if the bytecode has been stripped.
3) Before yielding from a coroutine, a window redraw message can be sent
to the AES. The dispatch of the subsequent window redraw message can then
be used to resume the coroutine. The AES will merge window redraw requests.
4) gembindl rcache.lua is set by default to store loaded modules in a weak
table only, therefore if the last remaining reference is in the weak table
they are subject to garbage collection. This can be altered using RCache
function set_keep(true).
