/*
 Copyright (c) 2014, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#if JSC_OBJC_API_ENABLED
#import <JavaScriptCore/JavaScriptCore.h>
#endif

#import "Document+Database.h"
#import "CHCSVParser.h"

#define kDocumentType_D3V @"net.pol-online.d3visualizer.visualization"  // Must match Info.plist
#define kDocumentType_SQLite3 @"SQLite3"  // Must match Info.plist
#define kDocumentType_CSV @"CSV"  // Must match Info.plist
#define kDocumentType_TSV @"TSV"  // Must match Info.plist

#define kMinVersion 1
#define kCurrentVersion 1

#define kKey_Version @"version"  // NSNumber - int
#define kKey_CSS @"css"  // NSString
#define kKey_JS @"js"  // NSString
#define kKey_SQL @"sql"  // NSString
#define kKey_WindowFrame @"window"  // NSString
#define kKey_WindowLayout @"layout"  // NSData
#define kKey_PrintInfo @"print"  // NSData

#define kEditDelay 0.5
#define kResizeDelay 0.25

@interface Document (NSTableViewDelegate) <NSTableViewDelegate>
@end

@interface Document (NSTableViewDataSource) <NSTableViewDataSource>
@end

@interface Document (CodeMirrorViewDelegate) <CodeMirrorViewDelegate>
@end

@interface Document (CHCSVParserDelegate) <CHCSVParserDelegate>
@end

static NSString* _defaultHTML = nil;
static NSString* _defaultCSS = nil;
static NSString* _defaultJS = nil;
static NSString* _defaultSQL = nil;
static NSString* _errorHTML = nil;

@implementation Document

@synthesize chartView=_chartView, cssView=_cssView, jsView=_jsView, sqlView=_sqlView, dataView=_dataView, tableColumn=_tableColumn,
            mainSplitView=_mainSplitView, leftSplitView=_leftSplitView, rightSplitView=_rightSplitView;

+ (void)initialize {
  _defaultHTML = [[NSString alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"] encoding:NSUTF8StringEncoding error:NULL];
  _defaultCSS = [[NSString alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"default" ofType:@"css"] encoding:NSUTF8StringEncoding error:NULL];
  _defaultJS = [[NSString alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"default" ofType:@"js"] encoding:NSUTF8StringEncoding error:NULL];
  _defaultSQL = [[NSString alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"default" ofType:@"sql"] encoding:NSUTF8StringEncoding error:NULL];
  _errorHTML = [[NSString alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"error" ofType:@"html"] encoding:NSUTF8StringEncoding error:NULL];
  
  [[NSUserDefaults standardUserDefaults] registerDefaults:@{
                                                            @"WebKitDeveloperExtras": @YES,
                                                            @"WebKit Web Inspector Setting - inspectorStartsAttached": @"false"
                                                            }];
}

+ (BOOL)autosavesInPlace {
  return YES;
}

+ (BOOL)preservesVersions {
  return YES;
}

+ (BOOL)autosavesDrafts {
  return YES;
}

+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString*)typeName {
  return YES;
}

- (void)_updateTimer:(NSTimer*)timer {
  NSMutableString* html = [NSMutableString stringWithString:_defaultHTML];
  [html replaceOccurrencesOfString:@"__CSS__" withString:_cssView.content options:0 range:NSMakeRange(0, html.length)];
  [html replaceOccurrencesOfString:@"__JS__" withString:_jsView.content options:0 range:NSMakeRange(0, html.length)];
  [[_chartView mainFrame] loadHTMLString:html baseURL:[[NSBundle mainBundle] resourceURL]];
}

- (id)init {
  if ((self = [super init])) {
    if (![self initializeDatabase]) {
      UNREACHABLE();
      return nil;
    }
    
    _updateTimer = [[NSTimer alloc] initWithFireDate:[NSDate distantFuture] interval:HUGE_VAL target:self selector:@selector(_updateTimer:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_updateTimer forMode:NSRunLoopCommonModes];
    
    _numberFormatter = [[NSNumberFormatter alloc] init];
    [_numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
    
    _css = _defaultCSS;
    _js = _defaultJS;
    _sql = _defaultSQL;
    
    self.hasUndoManager = NO;
    self.printInfo.orientation = NSPaperOrientationLandscape;
  }
  return self;
}

- (id)initWithType:(NSString*)typeName error:(NSError**)outError {
  if ((self = [super initWithType:typeName error:outError])) {
    if (![self createDatabaseTables:outError]) {
      return nil;
    }
  }
  return self;
}

- (void) dealloc {
  [self finalizeDatabase];
}

- (NSString*)windowNibName {
  return @"Document";
}

- (void)windowControllerDidLoadNib:(NSWindowController*)controller {
  [super windowControllerDidLoadNib:controller];
  
  if (_windowFrame) {
    [controller.window setFrameFromString:_windowFrame];
    _windowFrame = nil;
  }
  
  if (_windowLayout) {
    [[_mainSplitView.subviews objectAtIndex:0] setFrame:NSRectFromString([_windowLayout objectForKey:@"main1"])];
    [[_mainSplitView.subviews objectAtIndex:1] setFrame:NSRectFromString([_windowLayout objectForKey:@"main2"])];
    [_mainSplitView adjustSubviews];
    [[_leftSplitView.subviews objectAtIndex:0] setFrame:NSRectFromString([_windowLayout objectForKey:@"left1"])];
    [[_leftSplitView.subviews objectAtIndex:1] setFrame:NSRectFromString([_windowLayout objectForKey:@"left2"])];
    [_leftSplitView adjustSubviews];
    [[_rightSplitView.subviews objectAtIndex:0] setFrame:NSRectFromString([_windowLayout objectForKey:@"right1"])];
    [[_rightSplitView.subviews objectAtIndex:1] setFrame:NSRectFromString([_windowLayout objectForKey:@"right2"])];
    [[_rightSplitView.subviews objectAtIndex:2] setFrame:NSRectFromString([_windowLayout objectForKey:@"right3"])];
    [_rightSplitView adjustSubviews];
    _windowLayout = nil;
  }
  
  [_chartView setFrameLoadDelegate:self];
  [_chartView setUIDelegate:self];
  [[[_chartView mainFrame] frameView] setAllowsScrolling:NO];
  
  _cssView.delegate = self;
  _jsView.delegate = self;
  _sqlView.delegate = self;
  
  _archivedColumn = [NSKeyedArchiver archivedDataWithRootObject:_tableColumn];
}

- (NSWindow*)documentWindow {
  return [[[self windowControllers] firstObject] window];
}

- (void)_reloadContent {
  _cssView.content = _css ? _css : @"";
  _css = nil;
  _jsView.content = _js ? _js : @"";
  _js = nil;
  _sqlView.content = _sql ? _sql : @"";
  _sql = nil;
  [self _updateTimer:nil];
}

- (BOOL)readFromURL:(NSURL*)url ofType:(NSString*)typeName error:(NSError**)outError {
  CHECK([url isFileURL]);
  
  if ([typeName isEqualToString:kDocumentType_D3V] || [typeName isEqualToString:kDocumentType_SQLite3]) {
    if (![self readDatabaseFromPath:[url path] error:outError]) {
      return NO;
    }
  } else if ([typeName isEqualToString:kDocumentType_CSV] || [typeName isEqualToString:kDocumentType_TSV]) {
    NSStringEncoding encoding = 0;
    NSInputStream* stream = [[NSInputStream alloc] initWithFileAtPath:[url path]];
    unichar delimiter = [typeName isEqualToString:kDocumentType_TSV] ? '\t' : ',';
    CHCSVParser* parser = [[CHCSVParser alloc] initWithInputStream:stream usedEncoding:&encoding delimiter:delimiter];
    parser.sanitizesFields = YES;
    parser.delegate = self;
    [parser parse];
    if (_parseError) {
      if (outError) {
        *outError = _parseError;
      }
      return NO;
    }
  } else {
    UNREACHABLE();
  }
  
  if ([typeName isEqualToString:kDocumentType_D3V]) {
    NSNumber* version = [self getDatabaseValueForKey:kKey_Version];
    if (![version isKindOfClass:[NSNumber class]] || ([version intValue] < kMinVersion) || ([version intValue] > kCurrentVersion)) {
      UNREACHABLE();
      return NO;  // TODO: Handle error
    }
  } else {
    if (![self createDatabaseTables:outError]) {
      return NO;
    }
    self.fileURL = nil;
  }
  
  NSString* css = [self getDatabaseValueForKey:kKey_CSS];
  if ([css isKindOfClass:[NSString class]]) {
    _css = css;
  }
  
  NSString* js = [self getDatabaseValueForKey:kKey_JS];
  if ([js isKindOfClass:[NSString class]]) {
    _js = js;
  }
  
  NSString* sql = [self getDatabaseValueForKey:kKey_SQL];
  if ([sql isKindOfClass:[NSString class]]) {
    _sql = sql;
  }
  
  NSData* printInfo = [self getDatabaseValueForKey:kKey_PrintInfo];
  if ([printInfo isKindOfClass:[NSData class]]) {
    self.printInfo = [NSKeyedUnarchiver unarchiveObjectWithData:printInfo];
    [self updateChangeCount:NSChangeCleared];
  }
  
  if (_chartView) {
    [self _reloadContent];
  } else {
    NSString* windowFrame = [self getDatabaseValueForKey:kKey_WindowFrame];
    if ([windowFrame isKindOfClass:[NSString class]]) {
      _windowFrame = windowFrame;
    }
    
    NSData* windowLayout = [self getDatabaseValueForKey:kKey_WindowLayout];
    if ([windowLayout isKindOfClass:[NSData class]]) {
      _windowLayout = [NSKeyedUnarchiver unarchiveObjectWithData:windowLayout];
    }
  }
  
  return YES;
}

- (BOOL)writeToURL:(NSURL*)url ofType:(NSString*)typeName error:(NSError**)outError {
  CHECK([url isFileURL]);
  
  [self setDatabaseValue:@kCurrentVersion forKey:kKey_Version];
  
  [self setDatabaseValue:_cssView.content forKey:kKey_CSS];
  
  [self setDatabaseValue:_jsView.content forKey:kKey_JS];
  
  [self setDatabaseValue:_sqlView.content forKey:kKey_SQL];
  
  [self setDatabaseValue:[NSKeyedArchiver archivedDataWithRootObject:self.printInfo] forKey:kKey_PrintInfo];
  
  [self setDatabaseValue:[self.documentWindow stringWithSavedFrame] forKey:kKey_WindowFrame];
  
  NSDictionary* layout = @{
                           @"main1": NSStringFromRect([[_mainSplitView.subviews objectAtIndex:0] frame]),
                           @"main2": NSStringFromRect([[_mainSplitView.subviews objectAtIndex:1] frame]),
                           @"left1": NSStringFromRect([[_leftSplitView.subviews objectAtIndex:0] frame]),
                           @"left2": NSStringFromRect([[_leftSplitView.subviews objectAtIndex:1] frame]),
                           @"right1": NSStringFromRect([[_rightSplitView.subviews objectAtIndex:0] frame]),
                           @"right2": NSStringFromRect([[_rightSplitView.subviews objectAtIndex:1] frame]),
                           @"right3": NSStringFromRect([[_rightSplitView.subviews objectAtIndex:2] frame])
                           };
  [self setDatabaseValue:[NSKeyedArchiver archivedDataWithRootObject:layout] forKey:kKey_WindowLayout];
  
  return [self writeDatabaseToPath:[url path] error:outError];
}

- (NSPrintOperation*)printOperationWithSettings:(NSDictionary*)printSettings error:(NSError**)outError {
  NSView<WebDocumentView>* documentView = [[[_chartView mainFrame] frameView] documentView];
  NSPrintInfo* printInfo = [self.printInfo copy];
  [printInfo.printSettings addEntriesFromDictionary:printSettings];
  return [NSPrintOperation printOperationWithView:documentView printInfo:printInfo];
}

// TODO: Use PDF export feature from NSDocument in 10.9
- (IBAction)saveDocumentToPDF:(id)sender {
  NSSavePanel* savePanel = [NSSavePanel savePanel];
  [savePanel setAllowedFileTypes:@[@"pdf"]];
  [savePanel setNameFieldStringValue:[self.displayName stringByDeletingPathExtension]];
  [savePanel setDirectoryURL:self.fileURL];
  [savePanel beginSheetModalForWindow:self.documentWindow completionHandler:^(NSInteger result) {
    if (result == NSFileHandlingPanelOKButton) {
      NSView<WebDocumentView>* documentView = [[[_chartView mainFrame] frameView] documentView];
      NSData* data = [documentView dataWithPDFInsideRect:documentView.bounds];
      NSError* error = nil;
      if (![data writeToFile:[[savePanel URL] path] options:NSDataWritingAtomic error:&error]) {
        NSLog(@"Failed writing to PDF: %@", error);
      }
    }
  }];
}

- (BOOL)shouldRunSavePanelWithAccessoryView {
  return NO;
}

@end

@implementation Document (JavaScriptBindings)

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)selector {
  if (selector == @selector(ready)) {
    return NO;
  }
  if (selector == @selector(resize)) {
    return NO;
  }
  return YES;
}

- (void)ready {
  
  NSString* query = _sqlView.content;
  if (![_query isEqualToString:query]) {
    _data = [self executeDatabaseQuery:_sqlView.content error:NULL];  // TODO: Handle error
    
    for (NSTableColumn* column in [NSArray arrayWithArray:_dataView.tableColumns]) {
      [_dataView removeTableColumn:column];
    }
    if (_data) {
      if (_data.count) {
        NSDictionary* row = [_data objectAtIndex:0];
        for (NSString* key in [[row allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
          NSTableColumn* column = [NSKeyedUnarchiver unarchiveObjectWithData:_archivedColumn];
          column.identifier = key;
          [column.headerCell setStringValue:key];
          [column.dataCell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
          if ([[row objectForKey:key] isKindOfClass:[NSNumber class]]) {
            [column.dataCell setFormatter:_numberFormatter];
          }
          [_dataView addTableColumn:column];
        }
      }
    } else {
      [[_chartView mainFrame] loadAlternateHTMLString:_errorHTML baseURL:nil forUnreachableURL:nil];
    }
    [_dataView reloadData];
    
    _query = [query copy];
  }
  
  if (_data) {
    WebScriptObject* windowObject = [[_chartView mainFrame] windowObject];
    NSNumber* result = nil;
#if JSC_OBJC_API_ENABLED
    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber10_9) {
      CHECK([windowObject JSValue]);
      JSValue* value = [[windowObject JSValue] invokeMethod:@"_renderData" withArguments:@[_data]];
      if ([value isBoolean]) {
        result = [NSNumber numberWithBool:[value toBool]];
      }
    } else
#endif
    {
      NSData* json = [NSJSONSerialization dataWithJSONObject:_data options:0 error:NULL];
      CHECK(json);
      NSString* string = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
      CHECK(string);
      result = [windowObject callWebScriptMethod:@"_renderJSON" withArguments:@[string]];
    }
    if (![result isKindOfClass:[NSNumber class]] && [result boolValue]) {
      [[_chartView mainFrame] loadAlternateHTMLString:_errorHTML baseURL:nil forUnreachableURL:nil];
    }
  }
  
}

- (void)resize {
  [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kResizeDelay]];
}

@end

@implementation Document (WebFrameLoadDelegate)

- (void)webView:(WebView*)webView didClearWindowObject:(WebScriptObject*)windowObject forFrame:(WebFrame*)frame {
  [windowObject setValue:self forKey:@"_delegate"];
}

@end

@implementation Document (WebUIDelegate)

- (NSArray*)webView:(WebView*)sender contextMenuItemsForElement:(NSDictionary*)element defaultMenuItems:(NSArray*)defaultMenuItems {
  NSMutableArray* items = [NSMutableArray arrayWithArray:defaultMenuItems];
  [items removeObjectAtIndex:0];
  if ([[items firstObject] isSeparatorItem]) {
    [items removeObjectAtIndex:0];
  }
  return items;
}

@end

@implementation Document (NSTableViewDelegate)

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tableView {
  return NO;
}

@end

@implementation Document (NSTableViewDataSource)

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return _data.count;
}

- (id)tableView:(NSTableView*)tableView objectValueForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  return [[_data objectAtIndex:row] objectForKey:tableColumn.identifier];
}

@end

@implementation Document (CodeMirrorViewDelegate)

- (void)codeMirrorViewDidChangeContent:(CodeMirrorView*)view {
  [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kEditDelay]];
  
  if (_cssView.edited || _jsView.edited || _sqlView.edited) {
    [self updateChangeCount:NSChangeDone];
  } else {
    [self updateChangeCount:NSChangeCleared];
  }
}

- (void)codeMirrorViewDidFinishLoading:(CodeMirrorView*)view {
  view.tabSize = 2;
  view.indentUnit = 2;
  view.lineWrapping = YES;
  view.tabInsertsSpaces = YES;
  if (view == _cssView) {
    view.mimeType = @"text/css";
  } else if (view == _jsView) {
    view.mimeType = @"application/javascript";
  } else if (view == _sqlView) {
    view.mimeType = @"text/x-mysql";
  } else {
    UNREACHABLE();
  }
  
  if (_cssView.mimeType.length && _jsView.mimeType.length && _sqlView.mimeType.length) {  // Detect all editors are ready
    [self _reloadContent];
  }
}

@end

@implementation Document (CHCSVParserDelegate)

- (void)parserDidBeginDocument:(CHCSVParser*)parser {
  _headers = [[NSMutableArray alloc] init];
}

- (void)parser:(CHCSVParser*)parser didBeginLine:(NSUInteger)recordNumber {
  if (recordNumber > 1) {
    if (_line) {
      [_line removeAllObjects];
    } else {
      _line = [[NSMutableArray alloc] init];
    }
  }
}

- (void)parser:(CHCSVParser*)parser didReadField:(NSString*)field atIndex:(NSInteger)fieldIndex {
  if (_line) {
    [_line addObject:field];
  } else {
    [_headers addObject:field];
  }
}

- (void)parser:(CHCSVParser*)parser didEndLine:(NSUInteger)recordNumber {
  if (_line) {
    if (_line.count == _headers.count) {
      NSError* error;
      if (![self executeDatabaseStatement:_insertSQL withParameters:_line error:&error]) {
        _parseError = error;
        [parser cancelParsing];
      }
    } else if (![[_line firstObject] isEqualToString:@""]) {
      NSLog(@"Skipping line %lu: %@", recordNumber, _line);
      UNREACHABLE();
    }
  } else {
    NSMutableString* sql = [[NSMutableString alloc] init];
    [sql appendString:@"CREATE TABLE data ("];
    for (NSUInteger i = 0; i < _headers.count; ++i) {
      if (i > 0) {
        [sql appendString:@", "];
      }
      [sql appendFormat:@"'%@'", [_headers objectAtIndex:i]];
    }
    [sql appendString:@")"];
    NSError* error;
    if ([self executeDatabaseStatement:sql withParameters:nil error:&error]) {
      _insertSQL = [[NSMutableString alloc] init];
      [_insertSQL appendString:@"INSERT INTO data ("];
      for (NSUInteger i = 0; i < _headers.count; ++i) {
        if (i > 0) {
          [_insertSQL appendString:@", "];
        }
        [_insertSQL appendFormat:@"'%@'", [_headers objectAtIndex:i]];
      }
      [_insertSQL appendString:@") VALUES ("];
      for (NSUInteger i = 0; i < _headers.count; ++i) {
        if (i > 0) {
          [_insertSQL appendString:@", "];
        }
        [_insertSQL appendFormat:@"?%lu", i + 1];
      }
      [_insertSQL appendString:@")"];
    } else {
      _parseError = error;
      [parser cancelParsing];
    }
  }
}

- (void)parser:(CHCSVParser*)parser didFailWithError:(NSError*)error {
  _line = nil;
  _headers = nil;
  _parseError = error;
  _insertSQL = nil;
}

- (void)parserDidEndDocument:(CHCSVParser*)parser {
  _line = nil;
  _headers = nil;
  _insertSQL = nil;
}

@end
