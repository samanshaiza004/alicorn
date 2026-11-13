---
title: Your first native app
description: Build Alicorn's starter, change its UI, and run it in a native window.
---

The shortest route is the repository's native starter. After installing the
[prerequisites](/docs/getting-started/requirements), clone the repository if
you have not already:

~~~sh
git clone https://github.com/samanshaiza004/alicorn.git
cd alicorn
~~~

Run the starter with the script for your platform:

~~~sh
./tools/native_hello.sh
~~~

On Windows PowerShell:

~~~powershell
.\tools\native_hello.ps1
~~~

The runner builds the example and opens a native window. The source is
<code>examples/01_hello/main.odin</code>.

## The shape of an app

The starter uses the high-level <code>alicorn:ui</code> package. App data stays
in an ordinary Odin struct; the render procedure describes the visible
interface:

~~~odin
import ui "alicorn:ui"

App :: struct { saved: bool }

render :: proc(app: ^App, ctx: ^ui.UI) {
    if ui.column(ctx, padding=24, gap=12) {
        ui.text(ctx, "Hello, Alicorn")
        if ui.button(ctx, "Save") {
            app.saved = true
        }
    }
}

main :: proc() {
    app := App{}
    ui.run(&app, render, title="Alicorn", width=720, height=480)
}
~~~

Change the text or button label in the example and rerun the same command.
Then try [the form example](/docs/reference/api-and-examples#controls-and-layout)
and continue through the
[example progression](/docs/reference/api-and-examples).

## Where to go next

- [Runtime model](/docs/concepts/retained-runtime)
- [Invalidation and stable identity](/docs/concepts/invalidation)
- [Themes and custom controls](/docs/guides/themes-and-components)
