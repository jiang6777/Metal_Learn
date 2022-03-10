# Metal_Learn
This project realizes the rendering of real-time video stream through Metal, and the rendered video stream supports NV12, NV21, RGB, BGR and other video formats.

## Introduce
By learning the source code of WebRTC and sorting out the process of Metal rendering in WebRTC, I have improved Metal and encapsulated Metal rendering as CVTMetalView, which is easy to use.

## Ideas
In order to be compatible with many video frame formats, in CVTI420Buffer, I will convert YUV420, RGB and other data formats to I420 through the newI420Frame and toI420 methods, and then render the Y, U, V planes in Metal. This example is rendered by collecting data from a Mac computer camera.
