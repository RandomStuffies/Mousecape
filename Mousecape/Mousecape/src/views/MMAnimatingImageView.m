//
//  MMAnimatingImageView.m
//  Magic Mouse
//
//  Created by Alex Zielenski on 2/25/12.
//  Copyright (c) 2012 Alex Zielenski. All rights reserved.
//

#import "MMAnimatingImageView.h"
#import "MCSpriteLayer.h"
//#import "NSImage+BestRep.h"

static NSRect centerSizeInRect(NSSize size, NSRect rect) {
    return NSIntegralRect(NSMakeRect(NSMidX(rect) - size.width / 2, NSMidY(rect) - size.height / 2, size.width, size.height));
}

const char MCInvalidateContext;

@interface MMAnimatingImageView ()
@property (weak) MCSpriteLayer *spriteLayer;
- (void)_initialize;
- (void)_invalidateFrame;
- (void)_invalidateAnimation;
@end

@implementation MMAnimatingImageView
- (id)init {
	if ((self = [super init])) {
		[self _initialize];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self _initialize];
    }
    return self;
}

- (id)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self _initialize];
    }
    
    return self;
}

- (void)_initialize {
    self.shouldAnimate = YES;
    
//    [self registerTypes];
    
    self.layer = [[MCSpriteLayer alloc] init];
    self.wantsLayer = YES;
    self.layer.contentsGravity = kCAGravityCenter;
    self.layer.bounds = self.bounds;
    self.layer.autoresizingMask = kCALayerHeightSizable | kCALayerWidthSizable | kCALayerMinXMargin | kCALayerMinYMargin;
    self.layer.delegate = self;
    
    self.spriteLayer = (MCSpriteLayer *)self.layer;

    self.frameCount    = 1;
    self.frameDuration = 1;
    
    [self addObserver:self forKeyPath:@"image" options:0 context:(void *)&MCInvalidateContext];
    [self addObserver:self forKeyPath:@"placeholderImage" options:0 context:(void *)&MCInvalidateContext];
    [self addObserver:self forKeyPath:@"frameCount" options:0 context:(void *)&MCInvalidateContext];
    [self addObserver:self forKeyPath:@"frameDuration" options:0 context:(void *)&MCInvalidateContext];
    [self addObserver:self forKeyPath:@"shouldAnimate" options:0 context:NULL];
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:@"image"];
    [self removeObserver:self forKeyPath:@"placeholderImage"];
    [self removeObserver:self forKeyPath:@"frameCount"];
    [self removeObserver:self forKeyPath:@"frameDuration"];
    [self removeObserver:self forKeyPath:@"shouldAnimate"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &MCInvalidateContext) {
        if ([keyPath isEqualToString:@"image"] || [keyPath isEqualToString:@"placeholderImage"]) {
            self.spriteLayer.contents = !self.image ? self.placeholderImage : self.image;
        }
        [self _invalidateFrame];
        [self _invalidateAnimation];
    } else if ([keyPath isEqualToString:@"shouldAnimate"]) {
        [self _invalidateAnimation];
    }
}

- (BOOL)layer:(CALayer *)layer shouldInheritContentsScale:(CGFloat)newScale fromWindow:(NSWindow *)window {
    return self.scale == 0.0 || !self.image;
}

// Tell OSX that our view can accept images to be dragged in
- (void)registerTypes {
	[self registerForDraggedTypes:[NSArray arrayWithObjects:NSPasteboardTypeTIFF, NSPasteboardTypePNG, NSFilenamesPboardType, nil]];
}

- (void)viewDidMoveToWindow {
    [self _invalidateFrame];
}

#pragma mark - Invalidators

- (void)_invalidateFrame {
    CGFloat scale = self.scale;
    if (!self.scale || !self.image)
        scale = self.window.backingScaleFactor;
    self.layer.contentsScale = scale;
}

- (void)_invalidateAnimation {
    [self.spriteLayer removeAllAnimations];
    
    
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"sampleIndex"];
    BOOL none = (self.frameCount == 1 || !self.shouldAnimate);
    NSUInteger frameCount = none || !self.image ? 0 : self.frameCount;
    self.spriteLayer.frameCount = frameCount;

    anim.fromValue    = @(frameCount + 1);
    anim.toValue      = @(1);
    anim.byValue      = @(-1);
    anim.duration     = self.frameDuration * frameCount;
    anim.repeatCount  = none ? 0 : HUGE_VALF; // just keep repeating it
    anim.autoreverses = NO; // do 1, 2, 3, 4, 5, 1, 2, 3, 4, 5
    anim.removedOnCompletion = none;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self.spriteLayer addAnimation:anim forKey:@"sampleIndex"]; // start
}

- (id <CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
    return (id <CAAction>)[NSNull null];
}

#pragma mark - NSDragDestination

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	// Only thing we have to do here is confirm that the dragged file is an image. We use NSImage's +canInitWithPasteboard: and we also check to see there is only one item being dragged
	if ([self.delegate conformsToProtocol:@protocol(MMAnimatingImageViewDelegate)] &&  // No point in accepting the drop if the delegate doesn't support it/exist
		[NSImage canInitWithPasteboard:sender.draggingPasteboard] &&                   // Only Accept Images
		sender.draggingPasteboard.pasteboardItems.count == 1) {                        // Only accept one item
		return [self.delegate imageView:self draggingEntered:sender];
	}
	return NSDragOperationNone;
}

// Give the delegate some more control
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	if ([self.delegate conformsToProtocol:@protocol(MMAnimatingImageViewDelegate)]) {
		return [self.delegate imageView:self shouldPerformDragOperation:sender];
	}
	return NO;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	if ([self.delegate conformsToProtocol:@protocol(MMAnimatingImageViewDelegate)] &&  // Only do the operation if a delegate exists to actually set the image.
		[self.delegate imageView:self shouldPerformDragOperation:sender]) {            // Only do the operation if a delegate wants us to do the operation.
		
		// Get the image from the pasteboard
		NSImage *im = [[NSImage alloc] initWithPasteboard:sender.draggingPasteboard];
		
		// Make an array of the valid drops (NSBitmapImageRep)
		NSMutableArray *acceptedDrops = [NSMutableArray arrayWithCapacity:im.representations.count];
		for (NSImageRep *rep in im.representations) {
			if (![rep isKindOfClass:[NSBitmapImageRep class]]) // We don't want PDFs
				continue;
			
			[acceptedDrops addObject:rep];
			
		}
		
		if (acceptedDrops.count > 0) {
			// We already confirmed that the delegate conforms to the protocol above. Now we can let the delegate
			// decide what to do with the dropped images.
			[self.delegate imageView:self didAcceptDroppedImages:acceptedDrops];
		}
		
		return YES;
	}
	
	return NO;
}

@end
