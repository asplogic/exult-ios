#include "ios_utils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GamePadView.h"
#import "./SDL2-2.0.3/src/video/uikit/SDL_uikitappdelegate.h"
#include "Configuration.h"

#include <cassert>

static char docs_dir[512];
extern "C" int SDL_SendKeyboardKey(Uint8 state, SDL_Scancode scancode);

// Add a 'category' to the SDL app delegate class
@interface ExultAppDelegate : SDLUIKitDelegate
{
    UIWindow* window;
}
@property (nonatomic, retain) UIWindow *window;

@end

@implementation SDLUIKitDelegate (Exult)
+ (NSString *)getAppDelegateClassName
{
    //override this SDL method so an instance of our subclass is used
    return @"ExultAppDelegate";
}

@end

@implementation ExultAppDelegate
@synthesize window;

-(void) dealloc {
    [window release];
    [super dealloc];
}

@end

@interface UIManager : NSObject<UIAlertViewDelegate, KeyInputDelegate, GamePadButtonDelegate>
{
	TouchUI_iOS *touchUI;
	DPadView *dpad;
	GamePadButton *btn1;
	GamePadButton *btn2;
	SDL_Scancode recurringKeycode;
};

- (void)promptForName:(NSString*)name;

@end

@implementation UIManager

- (void)sendRecurringKeycode
{
	SDL_SendKeyboardKey(SDL_PRESSED, recurringKeycode);
	[self performSelector:@selector(sendRecurringKeycode) withObject:nil afterDelay:.5];
}

- (void)keydown:(SDL_Scancode)keycode
{
	SDL_SendKeyboardKey(SDL_PRESSED, keycode);
	recurringKeycode = keycode;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendRecurringKeycode) object:nil];
	[self performSelector:@selector(sendRecurringKeycode) withObject:nil afterDelay:.5];
}

- (void)keyup:(SDL_Scancode)keycode
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendRecurringKeycode) object:nil];
	SDL_SendKeyboardKey(SDL_RELEASED, keycode);
}

- (void)buttonDown:(GamePadButton*)btn
{
	SDL_SendKeyboardKey(SDL_PRESSED, (SDL_Scancode) [btn.keyCodes[0] integerValue] );
}

- (void)buttonUp:(GamePadButton*)btn
{
	SDL_SendKeyboardKey(SDL_RELEASED, (SDL_Scancode) [btn.keyCodes[0] integerValue] );
}

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (buttonIndex == [alert cancelButtonIndex]) {
		/* do nothing */
	} else {
		TouchUI::onTextInput([alert textFieldAtIndex:0].text.UTF8String);
	}
}

- (void)promptForName:(NSString*)name
{
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Name"
    	message:@"" delegate:self
    	cancelButtonTitle:@"Cancel"
	otherButtonTitles:@"OK", nil];
	[alert setAlertViewStyle:UIAlertViewStylePlainTextInput];
	UITextField *textField = [alert textFieldAtIndex:0];
	
	if ([textField respondsToSelector:@selector(inputAssistantItem)]) {
		textField.inputAssistantItem.trailingBarButtonGroups = @[];
		textField.inputAssistantItem.leadingBarButtonGroups  = @[];
	}

	if (name) {
		[textField setText:name];
	}
	[alert show];
	[alert release];
}

- (CGRect)calcRectForDPad
{
	UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
	UIViewController *controller = window.rootViewController;
	CGRect rcScreen = controller.view.bounds;
	CGSize sizeDpad = CGSizeMake(180, 180);
	float margin_bottom = 30;

	std::string str;
	float left = rcScreen.size.width - sizeDpad.width;
	config->value("config/iphoneos/dpad_location", str, "right");
	if (str == "no") {
		return CGRectZero;
	} else if (str == "left") {
		left = 0;
	}
	CGRect rcDpad = CGRectMake(
		left,
		rcScreen.size.height-sizeDpad.height-margin_bottom,
		sizeDpad.width,
		sizeDpad.height);
	return rcDpad;
}

- (void)onDpadLocationChanged
{
	dpad.frame = [self calcRectForDPad];
}


- (GamePadButton*)createButton:(NSString*)title keycode:(int)keycode rect:(CGRect)rect
{
	GamePadButton *btn = [[GamePadButton alloc] initWithFrame:rect];
	btn.keyCodes = @[@(keycode)];
	btn.images = @[
		[UIImage imageNamed:@"btn.png"],
		[UIImage imageNamed:@"btnpressed.png"],
	];
	btn.textColor = [UIColor whiteColor];
	btn.title = title;
	btn.delegate = self;
	return btn;
}

- (void)showGameControls
{
	if (dpad == nil) {
		dpad = [[DPadView alloc] initWithFrame:CGRectZero];
		dpad.images = @[
			[UIImage imageNamed:@"dpadglass.png"],
			[UIImage imageNamed:@"dpadglass-east.png"],
			[UIImage imageNamed:@"dpadglass-northeast.png"],
			[UIImage imageNamed:@"dpadglass-north.png"],
			[UIImage imageNamed:@"dpadglass-northwest.png"],
			[UIImage imageNamed:@"dpadglass-west.png"],
			[UIImage imageNamed:@"dpadglass-southwest.png"],
			[UIImage imageNamed:@"dpadglass-south.png"],
			[UIImage imageNamed:@"dpadglass-southeast.png"],
		];
		dpad.keyInput = self;
	}
	UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
	UIViewController *controller = window.rootViewController;

	dpad.frame = [self calcRectForDPad];
	[controller.view addSubview:dpad];
	
	dpad.alpha = 1;
}

- (void)hideGameControls
{
	dpad.alpha = 0;
}

- (void)showButtonControls
{
	if (btn1 == nil) {
		btn1 = [self createButton:@"ESC" keycode:(int)SDL_SCANCODE_ESCAPE rect:CGRectZero];
	}

	UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
	UIViewController *controller = window.rootViewController;

	CGRect rcScreen = controller.view.bounds;
	CGSize sizeButton = CGSizeMake(60,30);
	CGRect rcButton = CGRectMake(10, rcScreen.size.height-sizeButton.height, sizeButton.width, sizeButton.height);
	btn1.frame = rcButton;
	[controller.view addSubview:btn1];

	btn1.alpha = 1;
}

- (void)hideButtonControls
{
	btn1.alpha = 0;
}
@end


static UIManager *_defaultManager;

/* ---------------------------------------------------------------------- */
#pragma mark TouchUI iOS

TouchUI_iOS::TouchUI_iOS() : TouchUI()
{
	if (_defaultManager == nil) {
		_defaultManager = [[UIManager alloc] init];
	}
}

void TouchUI_iOS::promptForName(const char *name)
{
	if (name == NULL) {
		[_defaultManager promptForName:nil];
	} else {
		[_defaultManager promptForName:[NSString stringWithUTF8String:name]];
	}
}

void TouchUI_iOS::showGameControls()
{
	[_defaultManager showGameControls];
}

void TouchUI_iOS::hideGameControls()
{
	[_defaultManager hideGameControls];
}

void TouchUI_iOS::showButtonControls()
{
	[_defaultManager showButtonControls];
}

void TouchUI_iOS::hideButtonControls()
{
	[_defaultManager hideButtonControls];
}

void TouchUI_iOS::onDpadLocationChanged()
{
	[_defaultManager onDpadLocationChanged];
}

/* ---------------------------------------------------------------------- */

const char* ios_get_documents_dir()
{
	if (docs_dir[0] == 0) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *docDirectory = [paths objectAtIndex:0];
		strcpy(docs_dir, docDirectory.UTF8String);
		printf("Documents: %s\n", docs_dir);
	//	chdir(docs_dir);
//		*strncpy(docs_dir, , sizeof(docs_dir)-1) = 0;
	}
	return docs_dir;
}

void ios_open_url(const char *sUrl)
{
	NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:sUrl]];
	[[UIApplication sharedApplication] openURL:url];
}
