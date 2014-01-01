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

#import <sqlite3.h>

#import "Document+Database.h"

#define MAKE_SQLLITE3_ERROR(database) [NSError errorWithDomain:@"SQLite3" \
                                                          code:sqlite3_errcode(database) \
                                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(database)]}]

@implementation Document (Database)

- (BOOL)initializeDatabase {
  CHECK(_database == NULL);
  int result = sqlite3_open_v2(":memory:", &_database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL);
  return (result == SQLITE_OK);
}

- (BOOL)createDatabaseTables:(NSError**)outError {
  return [self executeDatabaseStatement:@"CREATE TABLE '_d3v' ('key' TEXT PRIMARY KEY, 'value')" withParameters:nil error:outError];
}

- (BOOL)writeDatabaseToPath:(NSString*)path error:(NSError**)outError {
  sqlite3* database = NULL;
  int result = sqlite3_open_v2([path fileSystemRepresentation], &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL);
  if (result == SQLITE_OK) {
    sqlite3_backup* backup = sqlite3_backup_init(database, "main", _database, "main");
    if (backup) {
      sqlite3_backup_step(backup, -1);
      sqlite3_backup_finish(backup);
      result = sqlite3_errcode(database);
    }
  }
  if ((result != SQLITE_OK) && outError) {
    *outError = MAKE_SQLLITE3_ERROR(database);
  }
  if (database) {
    sqlite3_close(database);
  }
  return (result == SQLITE_OK);
}

- (BOOL)readDatabaseFromPath:(NSString*)path error:(NSError**)outError {
  sqlite3* database = NULL;
  int result = sqlite3_open_v2([path fileSystemRepresentation], &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
  if (result == SQLITE_OK) {
    sqlite3_backup* backup = sqlite3_backup_init(_database, "main", database, "main");
    if (backup) {
      sqlite3_backup_step(backup, -1);
      sqlite3_backup_finish(backup);
      result = sqlite3_errcode(_database);
    }
  }
  if ((result != SQLITE_OK) && outError) {
    *outError = MAKE_SQLLITE3_ERROR(database);
  }
  if (database) {
    sqlite3_close(database);
  }
  return (result == SQLITE_OK);
}

static void _BindStatementParameterValue(sqlite3_stmt* statement, int index, id value) {
  if ([value isKindOfClass:[NSData class]]) {
    sqlite3_bind_blob(statement, index, [value bytes], [value length], SQLITE_STATIC);  // Equivalent to sqlite3_bind_null() for zero-length
  } else if ([value isKindOfClass:[NSString class]]) {
    sqlite3_bind_text(statement, index, [value UTF8String], -1, SQLITE_STATIC);
  } else if ([value isKindOfClass:[NSNumber class]]) {
    if (CFNumberIsFloatType((CFNumberRef)value)) {
      sqlite3_bind_double(statement, index, [value doubleValue]);
    } else {
      sqlite3_bind_int(statement, index, [value intValue]);
    }
  } else {
    UNREACHABLE();
  }
}

static id _GetStatementColumnValue(sqlite3_stmt* statement, int index) {
  id value = nil;
  switch (sqlite3_column_type(statement, index)) {
      
    case SQLITE_NULL: {
      value = [NSData data];
      break;
    }
      
    case SQLITE_INTEGER: {
      value = [NSNumber numberWithInt:sqlite3_column_int(statement, index)];
      break;
    }
      
    case SQLITE_FLOAT: {
      value = [NSNumber numberWithDouble:sqlite3_column_double(statement, index)];
      break;
    }
      
    case SQLITE_TEXT: {
      const unsigned char* text = sqlite3_column_text(statement, index);
      if (text) {
        value = [NSString stringWithUTF8String:(const char*)text];
      } else {
        UNREACHABLE();
      }
      break;
    }
      
    case SQLITE_BLOB: {
      const void* bytes = sqlite3_column_blob(statement, index);
      if (bytes) {
        int length = sqlite3_column_bytes(statement, index);
        value = [NSData dataWithBytes:bytes length:length];
      } else {
        UNREACHABLE();
      }
      break;
    }
      
  }
  return value;
}

- (void)setDatabaseValue:(id)value forKey:(NSString*)key {
  sqlite3_stmt* statement = NULL;
  if (value) {
    int result = sqlite3_prepare_v2(_database, "INSERT OR REPLACE INTO _d3v (key, value) VALUES (?1, ?2)", -1, &statement, NULL);
    if (result == SQLITE_OK) {
      sqlite3_bind_text(statement, 1, [key UTF8String], -1, SQLITE_STATIC);
      _BindStatementParameterValue(statement, 2, value);
      result = sqlite3_step(statement);
      sqlite3_finalize(statement);
    }
    if (result != SQLITE_DONE) {
      EXCEPTION(@"Failed writing database value '%@': %s (%i)", key, sqlite3_errmsg(_database), result);
    }
  } else {
    int result = sqlite3_prepare_v2(_database, "DELETE FROM _d3v WHERE key=?1", -1, &statement, NULL);
    if (result == SQLITE_OK) {
      sqlite3_bind_text(statement, 1, [key UTF8String], -1, SQLITE_STATIC);
      result = sqlite3_step(statement);
      sqlite3_finalize(statement);
    }
    if (result != SQLITE_DONE) {
      EXCEPTION(@"Failed deleting database value '%@': %s (%i)", key, sqlite3_errmsg(_database), result);
    }
  }
}

- (id)getDatabaseValueForKey:(NSString*)key {
  id value = nil;
  sqlite3_stmt* statement = NULL;
  int result = sqlite3_prepare_v2(_database, "SELECT value FROM _d3v WHERE key=?1", -1, &statement, NULL);
  if (result == SQLITE_OK) {
    sqlite3_bind_text(statement, 1, [key UTF8String], -1, SQLITE_STATIC);
    result = sqlite3_step(statement);
    if (result == SQLITE_ROW) {
      value = _GetStatementColumnValue(statement, 0);
      result = sqlite3_step(statement);
    }
    sqlite3_finalize(statement);
  }
  if (result != SQLITE_DONE) {
    EXCEPTION(@"Failed reading database value '%@': %s (%i)", key, sqlite3_errmsg(_database), result);
  }
  return value;
}

- (BOOL)executeDatabaseStatement:(NSString*)sql withParameters:(NSArray*)parameters error:(NSError**)outError {
  sqlite3_stmt* statement = NULL;
  int result = sqlite3_prepare_v2(_database, [sql UTF8String], -1, &statement, NULL);
  if (result == SQLITE_OK) {
    for (NSUInteger i = 0; i < parameters.count; ++i) {
      _BindStatementParameterValue(statement, i + 1, [parameters objectAtIndex:i]);
    }
    result = sqlite3_step(statement);
    if ((result != SQLITE_DONE) && outError) {
      *outError = MAKE_SQLLITE3_ERROR(_database);
    }
    sqlite3_finalize(statement);
  }
  return (result == SQLITE_DONE);
}

- (NSArray*)executeDatabaseQuery:(NSString*)sql error:(NSError**)outError {
  NSMutableArray* results = nil;
  sqlite3_stmt* statement = NULL;
  int result = sqlite3_prepare_v2(_database, [sql UTF8String], -1, &statement, NULL);
  if (result == SQLITE_OK) {
    results = [[NSMutableArray alloc] init];
    while (1) {
      result = sqlite3_step(statement);
      if (result != SQLITE_ROW) {
        break;
      }
      NSMutableDictionary* row = [[NSMutableDictionary alloc] init];
      int count = sqlite3_column_count(statement);
      for (int i = 0; i < count; ++i) {
        id object = nil;
        switch (sqlite3_column_type(statement, i)) {
          
          case SQLITE_NULL: {
            object = [[NSData alloc] init];
            break;
          }
          
          case SQLITE_INTEGER: {
            object = [[NSNumber alloc] initWithInt:sqlite3_column_int(statement, i)];
            break;
          }
          
          case SQLITE_FLOAT: {
            object = [[NSNumber alloc] initWithDouble:sqlite3_column_double(statement, i)];
            break;
          }
          
          case SQLITE_TEXT: {
            const unsigned char* text = sqlite3_column_text(statement, i);
            if (text) {
              object = [[NSString alloc] initWithCString:(const char*)text encoding:NSUTF8StringEncoding];
            }
            break;
          }
          
          case SQLITE_BLOB: {
            const void* bytes = sqlite3_column_blob(statement, i);
            if (bytes) {
              int length = sqlite3_column_bytes(statement, i);
              object = [[NSData alloc] initWithBytes:bytes length:length];
            }
            break;
          }
          
        }
        [row setObject:object forKey:[NSString stringWithUTF8String:sqlite3_column_name(statement, i)]];
      }
      [results addObject:row];
    }
    if ((result != SQLITE_DONE) && outError) {
      *outError = MAKE_SQLLITE3_ERROR(_database);
    }
    sqlite3_finalize(statement);
  } else if (outError) {
    *outError = MAKE_SQLLITE3_ERROR(_database);
  }
  return (result == SQLITE_DONE ? results : nil);
}

- (void)finalizeDatabase {
  CHECK(_database);
  sqlite3_close(_database);
  _database = NULL;
}

@end
