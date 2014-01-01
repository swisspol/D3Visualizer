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

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#include "CodeMirrorView.h"

typedef struct sqlite3 sqlite3;

@interface Document : NSDocument {
@private
  sqlite3* _database;
  NSTimer* _updateTimer;
  NSNumberFormatter* _numberFormatter;
  NSData* _archivedColumn;
  NSString* _windowFrame;
  NSDictionary* _windowLayout;
  NSString* _css;
  NSString* _js;
  NSString* _sql;
  NSString* _query;
  NSArray* _data;
  NSMutableArray* _headers;
  NSMutableArray* _line;
  NSError* _parseError;
  NSMutableString* _insertSQL;
}
@property(nonatomic, assign) IBOutlet WebView* chartView;
@property(nonatomic, assign) IBOutlet CodeMirrorView* cssView;
@property(nonatomic, assign) IBOutlet CodeMirrorView* jsView;
@property(nonatomic, assign) IBOutlet CodeMirrorView* sqlView;
@property(nonatomic, assign) IBOutlet NSTableView* dataView;
@property(nonatomic, assign) IBOutlet NSTableColumn* tableColumn;
@property(nonatomic, assign) IBOutlet NSSplitView* mainSplitView;
@property(nonatomic, assign) IBOutlet NSSplitView* leftSplitView;
@property(nonatomic, assign) IBOutlet NSSplitView* rightSplitView;
@end
