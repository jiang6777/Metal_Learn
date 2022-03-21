# Metal_Learn
This project realizes the rendering of real-time video stream through Metal, and the rendered video stream supports NV12, NV21, RGB, BGR and other video formats，Although the Metal rendering of this project only shows the rendering of the camera on the Mac platform, the iOS platform is also supported.

## Ideas
In order to be compatible with many video frame formats, in CVTI420Buffer, I will convert YUV420, RGB and other data formats to I420 through the newI420Frame and toI420 methods, and then render the Y, U, V planes in Metal. This example is rendered by collecting data from a Mac computer camera.

## Usage
The specific usage of tmalview is as follows:

    if ([CVTMetalView isMetalAvailable]) {

         CGFloat height = self. view. frame. size. width * 9 / 16.0;

         self. metalView = [[CVTMetalView alloc] initWithFrame:NSMakeRect(0, 0, self.view.frame.size.width, height)];

         self. metalView. delegate = self;

         self. metalView. wantsLayer = YES;

         self. metalView. layer. backgroundColor = [NSColor blackColor]. CGColor;

         [self.view addSubview:self.metalView];

     }
## Achievement display
![Metal icon](https://github.com/jiang6777/Metal_Learn/blob/main/metal.png)
![Metal video](https://github.com/jiang6777/Metal_Learn/blob/main/metal1.mp4)


## End
If you find any problems during use, please send me an email message jiang677@yeah.net, it is not easy to create, if you think it can help you, I hope you can appreciate it, thank you
![My QR code](https://github.com/jiang6777/Metal_Learn/blob/main/thanks.png)
