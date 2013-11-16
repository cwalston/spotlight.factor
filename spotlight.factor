! (C) 2013 Charles Alston.
USING: accessors arrays byte-arrays fry google.search io
io.encodings.utf8 io.launcher kernel locals make namespaces
sequences sequences.generalizations splitting strings
unicode.categories vectors ;
FROM: webbrowser => open-file open-url ;
IN: spotlight

! *** searching on os x via spotlight metadata index, & managing indexing from factor ***
! *** mac os x 10.6.8 & later: implementing mdfind, mdls, mdutil, mdimport ***
! mdfind, mdls, mdutil, mdimport take a query on the stack
! & return a sequence of result strings

! -----
! TO DO:
! -need to test sudo-mdutil; intercept auth prompt
! -work out API call to MDSchemaCopyAllAttributes()
! -handle case-sensitivity properly (OS X)
! -test composing variant shell command constructions,
!  i.e., those which do or don't need spaces, parens,
!  single quotes, etc. (work through examples at end of file)
! -access o.e.d & calculator through spotlight
! -emit some sort of 'not-found' msg for unsuccessful search
! -trap errors! ...
! -----

SYMBOL: search-vec
: default-search-vec ( -- vector ) { "-onlyin" "/" } >vector ;
: search-vec! ( -- ) search-vec [ default-search-vec ] initialize ;
: get-search-vec ( -- vector ) search-vec! search-vec get ;
: reset-search-vec ( -- ) default-search-vec search-vec set ;
! change the search path
:: new-search-path ( my-path -- )
      reset-search-vec
      "/" search-vec get remove! my-path suffix! drop ;


! ***********************  mdfind  ***********************
! Usage: mdfind [-live] [-count] [-onlyin directory] [-name fileName | -s smartFolderName | query]
! list the files matching the query
! query can be an expression or a sequence of words
!   -live             Query should stay active
!   -count            Query only reports matching items count
!   -onlyin <dir>     Search only within given directory
!   -name <name>      Search on file name only
!   -s <name>         Show contents of smart folder <name>
!   -0                Use NUL (``\0'') as a path separator, for use with xargs -0.

! example:  mdfind image
! example:  mdfind -onlyin ~ image
! example:  mdfind -name stdlib.h
! example:  mdfind "kMDItemAuthor == '*MyFavoriteAuthor*'"
! example:  mdfind -live MyFavoriteAuthor
! -------
! example queries (some return faster than others):
! *** Return all files that have been modified today:
!     "date:today" mdfind
! *** Return all files that have been modified in the last 3 days:
! "kMDItemFSContentChangeDate >= $time.today (-3)" mdfind
! *** filename with spaces, e.g.,
! "Finding Joy in Combinators.pdf" "kMDItemFSName" by-attribute mdfind
! *** filename without spaces , e.g.,
! "libfactor.dylib" mdfind
! *** phrase with spaces, e.g.,
! "Building Factor from source" mdfind
! *** phrase or term without spaces, e.g.,
! "call-effect-unsafe" mdfind
! "metadata" mdfind
! *** terms in a document:
! "Document cocoa.messages selector"  mdfind
! *** all documents:
! "Document" mdfind - (long wait if there are lots).
! *** "pdf date:yesterday" mdfind
! *** "Dylan" "kMDItemComposer" by-attribute mdfind
! *** others, as per metadata attribute (see below), e.g.,
! "com.microsoft.word.doc" "kMDItemContentType" by-attribute mdfind
! -------

:: by-attribute ( item-name attr-name -- string )
      attr-name " == " append
      item-name "'" "'" surround append ;

:: <md-command> ( query cmd -- array )  ! 3 elems- cmd, path, query
     get-search-vec query suffix cmd prefix ;

! once a command is built, this does the work
: utf8-stream-lines ( command -- seq )
         utf8 [ lines ] with-process-reader ;

: mdfind ( query -- results )
     "mdfind" <md-command>  ! ( -- array )
     utf8-stream-lines ;

! ***********************  mdls  ***********************
! *** getting Uniform Type Identifiers and
!     other Metadata of a Given File ***

! example:
! "/Users/cwalston/factor/basis/ascii/ascii.factor" mdls

: mdls ( absfilepath -- seq )
    "mdls" swap 2array utf8-stream-lines ;

! ***********************  mdutil  ***********************
! *** Re-indexing Spotlight ***
! ➜  ~ git:(master) ✗ mdutil
! Usage: mdutil -pEsa -i (on|off) volume ...
!   Utility to manage Spotlight indexes.
!   -p		Publish metadata.
!   -i (on|off)	Turn indexing on or off.
!   -E		Erase and rebuild index.
!   -s		Print indexing status.
!   -a		Apply command to all volumes.
!   -v		Display verbose information.
! NOTE: Run as owner for network homes, otherwise run as root.
! ➜  ~ git:(master) ✗

! "sudo mdutil -E /
! This will re-index every mounted volume on the Mac, including hard
! drives, disk images, external drives, etc. Specific drives can be chosen
! by pointing to them in /Volumes/, to only rebuild the primary Macintosh HD:
! sudo mdutil -E /Volumes/Macintosh\ HD/
! To re-index an external drive named “External” the command would be:
! sudo mdutil -E /Volumes/External/
! Use of the mdutil command will spin up mds and mdworker
! processes as Spotlight goes to work."

! example:
! "/Volumes/Jurassic Grad - Spare Change" md-re-index
! returned: ( -- { "/Volumes/Jurassic Grad - Spare Change:" "\tIndexing enabled. " } )
! *** N.B. -
! this starts indexing as intended, but spotlight often has the irritating habit
! of indexing 'til the cows come home! i succeeded in spanking that behavior to a halt
! by quitting the mds system process in activity monitor.
! TIP: google "Spotless", a well-recommended shareware app that knows how to manage the beast.

:: (mdutil) ( flags on|off volume root/owner -- seq )
     root/owner flags "-" prepend "-i" on|off volume 5 narray
    utf8-stream-lines ;

: mdutil ( flags on|off volume -- seq )
    "mdutil" (mdutil) ;

! NEEDS TESTING - how to intercept authentication prompt?
: sudo-mdutil ( flags on|off volume -- seq )
    "sudo mdutil" (mdutil) ;

! ***********************  mdimport  ***********************
! *** Individually Re-indexing Selected Files ***
! ➜  ~ git:(master) ✗ mdimport
! Usage: mdimport [OPTION] path
!   -d debugLevel Integer between 1-4
!   -g plugin     Import files using the listed plugin, rather than the system installed plugins.
!   -p            Print out performance information gathered during the run
!   -A            Print out the list of all of the attributes and exit
!   -X            Print out the schema file and exit
!   -L            Print out the List of plugins that we are going to use and exit
!   -r            Ask the server to reimport files for UTIs claimed by the listed plugin.
!   -n            Don't send the imported attributes to the data store.
! ➜  ~ git:(master) ✗

! "In rare cases, Spotlight can miss a file during index, so rather than
! re-index an entire drive you can also manually add an individual file to
! the search index with the mdimport command:
! mdimport /path/to/file
! The mdimport command can be used on directories as well."

! a simple, no options example - touch file & retrieve its MetaData:
! "/Users/cwalston/factor/mdimport-test" [ touch-file ] keep [ "" mdimport ] keep mdls

! or just:
! "/Users/cwalston/factor/mdimport-test" "-p" mdimport

:: mdimport ( abspath options -- seq )
      "mdimport" 1vector options dup empty? not ! ( -- vector opt ? )
      [ suffix! ] [ drop ] if  abspath suffix!
      utf8-stream-lines ;

! **** ANCILLARY INFO, MOTLEY EXAMPLES ***
! instruct mds (MetaDataServer) to clear out the metadata cache and rebuild from scratch,
! using this command run from Terminal: sudo mdutil -avE
!
! *** AT COMMAND LINE ON OS X 10.6.8 ***
! mdfind USAGE:
! ➜  ~ git:(master) ✗ mdfind
! mdfind: no query specified.
! Usage: mdfind [-live] [-count] [-onlyin directory] [-name fileName | -s smartFolderName | query]
! list the files matching the query
! query can be an expression or a sequence of words
!   -live             Query should stay active
!   -count            Query only reports matching items count
!   -onlyin <dir>     Search only within given directory
!   -name <name>      Search on file name only
!   -s <name>         Show contents of smart folder <name>
!   -0                Use NUL (``\0'') as a path separator, for use with xargs -0.
! ***NOT AVAILABLE ON 10.6.8??? --
!   -literal          Force the provided query string to be taken as a literal query
!                     string, without interpretation.
!
!   -interpret        Force the provided query string to be interpreted as if the user
!                     had typed the string into the Spotlight menu.
!                     For example, the string "search" would produce the following
!                     query string:
!                     (* = search* cdw || kMDItemTextContent = search* cdw)
!
!
! example:  mdfind image (--OR mdfind "mdfind USAGE:" FOR PHRASES)
! example:  mdfind -onlyin ~ image
! example:  mdfind -name stdlib.h
! example:  mdfind "kMDItemAuthor == '*MyFavoriteAuthor*'" (--OR e.g., mdfind 'kMDItemAuthor == "Henry David Thoreau"' )
! example:  mdfind -live MyFavoriteAuthor
!
! ➜  ~ git:(master) ✗
! ***************** mdfind command line examples *****************
! name:file.txt
! kind:"jpeg image" (kind:jpg or *.jpg doesn't work)
! date:today
! date:"this week" (date:week doesn't work)
! modified:12/31/11
! kind:video AND size:<100000
! created:12/1/11-12/31/11
!
! Spotlight Keywords-
!   These can be included in the query expression to limit the type
!   of documents returned:
!
!   Applications 	kind:application, kind:applications, kind:app
!   Audio/Music 	kind:audio, kind:music
!   Bookmarks 	  	kind:bookmark, kind:bookmarks
!   Contacts 		kind:contact, kind:contacts
!   Email 		    kind:email, kind:emails, kind:mail message,
!                   kind:mail messages
!   Folders 	 	kind:folder, kind:folders
!   Fonts 		    kind:font, kind:fonts
!   iCal Events 	kind:event, kind:events
!   iCal To Dos 	kind:todo, kind:todos, kind:to do, kind:to dos
!   Images 		    kind:image, kind:images
!   Movies 		    kind:movie, kind:movies
!   PDF 		    kind:pdf, kind:pdfs
!   Preferences 	kind:system preferences, kind:preferences
!   Presentations kind:presentations, kind:presentation
!
! Date Keywords-
!   These can be included in the query expression to limit the age
!   of documents returned:
!
!   date:today 		    $time.today()
!   date:yesterday 	  	.yesterday()
!   date:this week 		.this_week()
!   date:this month 	.this_month()
!   date:this year 		.this_year()
!   date:tomorrow 		.tomorrow()
!   date:next month 	.next_month()
!   date:next week 	  	.next_week()
!   date:next year 		.next_year()
!
! Boolean Operators-
! By default mdfind will AND together elements of the query string.
!
!   | (OR) 		To return items that match either word, use the pipe character:
!               stringA|stringB
!   - (NOT) 	To exclude documents that match a string -string
!   == 		  	“equal”
!   = 		  	“not equal”
!   < and > 	“less” or “more than”
!   <= and >= 	“less than or equal” or “more than or equal”
!
! lenin|trotsky will find documents mentioning either Lenin or Trotsky
! lenin(-stalin) will find documents mentioning Lenin, but not, thankfully, Stalin
! lenin|trotsky(-stalin) will find documents mentioning either Lenin or Trotsky, but not Stalin
!
! Returns all files with any metadata attribute value matching the string "image":
! $ mdfind image
!
! Return all files that contain "Len Deighton" in the kMDItemAuthor metadata attribute:
! $ mdfind "kMDItemAuthor == '*Len Deighton*'"
!
! Return all files with any metadata attribute value matching the string
! "skateboard". The find continues to run after gathering the initial results,
! providing a count of the number of files that match the query.
! $ mdfind -live skateboard
!
! Return all Microsoft.Word document files:
! $ mdfind "kMDItemContentType == 'com.microsoft.word.doc'"
!
! Return files where the composer name includes 'Eno'
! (non case sensitive search):
! $ mdfind 'kMDItemComposer = "*ENO*"c'
!
! Return all image files matching the words 'maude' and 'paris':
! $ mdfind "kind:images maude paris"
!
! Return all image files last edited yesterday:
! $ mdfind "kind:image date:yesterday"
!
! Return all files in the users home folder (~) that have been modified in the
! last 3 days:
! $ mdfind -onlyin ~ 'kMDItemFSContentChangeDate >= $time.today (-3)'
!
! mdfind '"exact phrase"'
!
! mdfind kMDItemFSName=\*.scpt
! mdfind 'kMDItemFSName=*' -onlyin . # doesn't include hidden files
! mdfind kMDItemFSName=.DS_Store -0 | xargs -0 rm
! mdfind -0 -onlyin ~/Music 'kMDItemFSName=*.mp3&&kMDItemAudioBitRate<=192000' | xargs -0 mdls -name kMDItemAlbum | sort | uniq
!
! mdfind kMDItemContentType=com.apple.application-bundle -onlyin /usr/local
! mdfind kMDItemContentTypeTree=com.apple.bundle
! mdfind kMDItemContentTypeTree=public.movie
!
! mdfind 'kMDItemTextContent="*expose*"cd' # ignore case and diacritics
! mdfind kMDItemTextContent=*LSUIElement* -onlyin ~/Projects/applepdfs/
!
! mdfind 'kMDItemFSSize>=5000&&kMDItemFSSize<=5005'
!
! mdfind 'kMDItemFSContentChangeDate>=$time.iso(2012-04-13T13:44Z)'
!
! mdfind 'kMDItemFSCreationDate>=$time.now(-3600)'
!
! mdfind 'kMDItemKind=*movie&&kMDItemPixelHeight>=720'
!
! mdfind 'kMDItemFSInvisible=1||kMDItemFSInvisible=0' -onlyin . # includes hidden files
!
! mdfind 'kMDItemURL=*web.archive.org*page*' -onlyin ~/Library/Caches/Metadata/Safari/History
!
! mdfind 'kMDItemFSSize>=1e8&&kMDItemContentTypeTree=public.directory'
!
! mdfind kind:pdf
!
! mdfind 'kMDItemFSLabel>0' # items with color labels
!
! mdfind -onlyin / # like -onlyin /Volumes/Macintosh\ HD
!
! mdfind "$(PlistBuddy -c 'Print RawQuery' test.savedSearch)"
!
! sudo mdfind com_apple_backup_excludeItem=com.apple.backupd
!
! *** N.B. - SOME EXAMPLES © Copyright SS64.com 1999-2013 Some rights reserved ***
