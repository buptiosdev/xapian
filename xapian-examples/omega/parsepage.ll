/* parsepage.ll: scanner for page templates
 *
 * ----START-LICENCE----
 * Copyright 1999,2000 BrightStation PLC
 * 
 * This program is free software; you can redistribute it and/or 
 * modify it under the terms of the GNU General Public License as 
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
 * USA
 * -----END-LICENCE-----
 */

%option noyywrap

/* FIXME: close yyin? */

%{
#include "main.h"
#include "query.h"

#include <fcntl.h>
#include <sys/stat.h>

/* limit on mset size (as given in espec) */
#define MLIMIT 1000 // FIXME: deeply broken

#define YY_DECL \
 void print_query_page(const string &page, long int first, long int size)

#define yyterminate() return

#define YY_NEVER_INTERACTIVE 1

// print string to stdout, with " replaced by &#34;
// FIXME: tidy up?
static void
print_escaping_dquotes(const string &str)
{
    for (size_t i = 0; i < str.size(); i++) {
	char ch = str[i];
	if (ch == '"') {
	    cout << "&#34;";
	    continue;
	}
	cout << ch;
    }
}

/* pretty print numbers with thousands separated */
/* NB only handles %ld and %d with no width or flag specifiers... */
static void
pretty_printf(const char *p, int *a)
{
    char ch;
    while ((ch = *p++)) {
	if (ch == '%') {
	    ch = *p++;
	    if (ch == 'l') ch = *p++;
	    if (ch == 'd') {
		char buf[16];
		char *q;
		int len;
		sprintf(buf, "%d", *a++);
		len = strlen(buf);
		q = buf;
		while ((ch = *q++)) {
		    cout << ch;
		    if (--len && len % 3 == 0) cout << thou_sep;
		}
		continue;
	    }
	}
	cout << ch;
    }
}

%}

%%

%{
    long int last = 0;

    string tmp = option["gif_dir"];
    if (tmp != "") gif_dir = tmp;
    if ((yyin = page_fopen(page)) == NULL) return;
%}

\\GIF_DIR {
    cout << gif_dir;
}
\\PROB {
    print_escaping_dquotes(raw_prob);
}
\\SCRIPT_NAME {
    // \SCRIPT_NAME is the pathname we were invoked with
    char *p = getenv("SCRIPT_NAME");
    // we're probably in test mode, or the server's crap
    if (p == NULL) p = "fx";
    cout << p;
}
\\TOPDOC {
    cout << first;
}
\\VERSION {
    cout << FX_VERSION_STRING << endl;
}
\\SAVE {
    /*** save DB name **/
    if (db_name != default_db_name)
	cout << "<INPUT TYPE=hidden NAME=DB VALUE=\"" << db_name << "\">\n";

    /*** save top doc no. ***/
    if (first != 0)
	cout << "<INPUT TYPE=hidden NAME=TOPDOC VALUE=" << first << ">\n";
       
    /*** save maxhits ***/
    if (size != 10)
	cout << "<INPUT TYPE=hidden NAME=MAXHITS VALUE=" << size << ">\n";
    
    /*** save fmt ***/
    if (!fmt.empty())
	cout << "<INPUT TYPE=hidden NAME=FMT VALUE=\"" << fmt << "\">\n";
    
    /*** save prob query ***/
    if (!new_terms.empty()) {
	cout << "<INPUT TYPE=hidden NAME=OLDP VALUE=\"";
	vector<om_termname>::const_iterator i;
	for (i = new_terms.begin(); i != new_terms.end(); i++)
	    cout << *i << '.';
	cout << "\">\n";
    }

    // save ticked documents which don't have checkboxes displayed
    map <om_docid, bool>::const_iterator i;
    for (i = ticked.begin(); i != ticked.end(); i++) {
        if (i->second)
	    cout << "<INPUT TYPE=hidden NAME=R VALUE=" << i->first << ">\n";
    }
}
\\PREVOFF.*/[\\\n\r] {
    if (first == 0)
	cout << "<img " << string(yytext + 8, yyleng - 8) << ">\n";
}
\\NEXTOFF.*/[\\\n\r] {
    if (last >= msize - 1)
	cout << "<img " << string(yytext + 8, yyleng - 8) << ">\n";
}
\\PREV.*/[\\\n\r] {
    if (first > 0) {
	long int new_first;
	new_first = first - size;
	if (new_first < 0) new_first = 0;
			
	cout << "<INPUT NAME=\"&lt;\" "
	     << string(yytext + 5, yyleng - 5) << ">\n";
    }
}
\\NEXT.*/[\\\n\r] {
    if (last < msize - 1)
	cout << "<INPUT NAME=\"&gt;\" "
	     << string(yytext + 5, yyleng - 5) << ">\n";
}
\\MSIZE {
    cout << msize;
}
\\PAGES.[A-Z] { // T for text, G for graphical
    print_page_links(yytext[7], size, first);
}
\\STATLINE {
    if (msize == 0 && new_terms.empty()) {
	// eat to next newline (or EOF)
	int c;
	do c = yyinput(); while (c != '\n' && c != EOF);
    }
}
\\STAT[02as].*$ {
    int arg[3];
    bool print = false;
    arg[0] = first + 1;
    arg[1] = last + 1;
    arg[2] = msize;
    string text = string(yytext + 6, yyleng - 6);
    /* We're doing:
     * \STAT0 none
     * \STAT2 returning some matches from over n
     * \STATa returning all matches from n
     * \STATs returning some (but not all) matches from n
     * \STATLINE like \HITLINE but enabled when any one of the
     *        \STATx codes fires
     */
    switch (yytext[5]) {
     case '0': /* followed by string */
	if (msize == 0 && !new_terms.empty()) cout << text;
	break;
     case '2':
	/* used to be >= - now use an exact compare since MTOTAL
	 * may have given us the full figure.  If MTOTAL works and
	 * we got exactly MLIMIT hits, this will misreport... */
	if (msize == MLIMIT) print = true;
	break;
     case 'a':
	/* used to be < MLIMIT - now use an exact compare since MTOTAL
	 * may have given us the full figure.  If MTOTAL works and
	 * we got exactly MLIMIT hits, this will misreport... */
	/* FIXME: could use Mike Gatford's "1001" trick */
	if (0 < msize && msize != MLIMIT &&
	    (first == 0 && last + 1 == msize)) {	       
	    arg[0] = msize;
	    print = true;
	}
	break;
     case 's':
	/* used to be < MLIMIT - now use an exact compare since MTOTAL
	 * may have given us the full figure.  If MTOTAL works and
	 * we got exactly MLIMIT hits, this will misreport... */
	/* FIXME: could use Mike Gatford's "1001" trick */
	if (0 < msize && msize != MLIMIT &&
	    !(first == 0 && last + 1 == msize)) print = true;
	break;
    }
    if (print) pretty_printf(text.c_str(), arg);
}
\\HITLINE {
    if (!msize) {
	// eat to next newline (or EOF)
	int c;
	do c = yyinput(); while (c != '\n' && c != EOF);
    }
}
\\HITS {
    long int m;
    const char *q;
    int ch;
			
    query_string = "?DB=";
    query_string += db_name;
    query_string += "&P=";
    q = raw_prob.c_str();
    while ((ch = *q++) != '\0') {
	switch (ch) {
	 case '+':
	    query_string += "%2b";
	    break;
	 case '"':
	    query_string += "%22";
	    break;
	 case ' ':
	    ch = '+';
	    /* fall through */
	 default:
	    query_string += ch;
	}
    }
    /* add any boolean terms */
    map <char, string>::const_iterator i;			 
    for (i = filter_map.begin(); i != filter_map.end(); i++) {
	query_string += "&B=";
	query_string += i->second;
    }

    struct stat st;
    int fd = open(fmtfile.c_str(), O_RDONLY);
    if (fd >= 0) {
	if (fstat(fd, &st) == 0 && st.st_size) {
	    char *p;
	    p = (char*)malloc(st.st_size + 1);
	    if (p) {
		if (read(fd, p, st.st_size) == st.st_size) {
		    p[st.st_size] = '\0';
		    fmtstr = p;
		}
	    }
	}
	close(fd);
    }

    for (m = first; m <= last; m++) print_caption(m);
}
\\MAXHITS[0-9]+ {
    // item in max hits selector box */
    // expect 3 digits in FX, but allow more or less
    string num = string(yytext + 8, yyleng - 8);
    if (size == atoi(num.c_str())) cout << "SELECTED";
}
\\OSELECT[AO] {
    if ((op == OM_MOP_AND) ^! (yytext[8] == 'A')) cout << "SELECTED";
}
\\TOPTERMS {
    // Olly's expand on query page idea
    if (msize) {
    	OmESet eset;
	ExpandDeciderFerret decider;

	if (rset->items.size()) {
#ifdef DEBUG
	    cout << "Expanding with " << rset->get_rsize() << " ids" << endl;
#endif
	    eset = enquire->get_eset(30, *rset, 0, &decider);
	} else {
	    // invent an rset
	    OmRSet tmp;
	    
	    for (int m = min(4, int(msize) - 1); m >= 0; m--) {
#ifdef DEBUG
		cout << "Autotopterm id: " << mset.items[m].did << endl;
#endif
		tmp.add_document(mset.items[m].did);
	    }
		
	    eset = enquire->get_eset(30, tmp, 0, &decider);
	}

	int c = 0;
	vector<OmESetItem>::const_iterator i;
#ifdef DEBUG
	for (i = eset.items.begin(); i != eset.items.end(); i++) {
	    cout << i->tname << ":" << i->wt << " " << endl;
	}
#endif
	for (i = eset.items.begin(); i != eset.items.end(); i++) {
	    string tname = i->tname;

	    // Ignore terms in the query already
	    // FIXME - make this part of the decision function - then we
	    // can set the size of the eset to be calculated to 20.
	    if (matching_map.find(tname) != matching_map.end()) continue;

	    cout << "<INPUT TYPE=checkbox NAME=X VALUE=\"" << tname
		 << ".\" onClick=\"C(this)\">&nbsp;" << tname << ". ";
	    if (++c >= 20) break;
	}
	if (c)
	    cout << "<BR><NOSCRIPT><INPUT TYPE=hidden NAME=ADD VALUE=1>"
	            "</NOSCRIPT>\n";
    }
}
\\DOMATCH {
    /* don't rerun query if we ran it earlier */
    if (msize < 0) {
	run_query(first, size);
    }

    if (first > msize) first = 0;
    
    if (first + size < msize)
	last = first + size - 1;
    else
	last = msize - 1;
}
\\FER-WHERE {
    /* ferret countrycode picker */
    static const char *doms[] = {
	"ad", "al", "am", "at", "az", "ba", "be", "bg",
	"by", "ch", "cy", "cz", "de", "dk", "ee", "es",
	"fi", "fo", "fr", "ge", "gi", "gl",
	"gr", "hr", "hu", "ie", "is", "it",
	"li", "lt", "lu", "lv", "mc", "mk", "mt", "mo",
	"nl", "no", "pl", "pt", "ro", "ru", "se", "si",
	"sk", "sm", "su", "tr", "ua", "uk+", "va", "yu",
	NULL /* Now in uk+: "gb", "gg", "im", "je", "uk" */
    };
    do_picker('N', doms);
}
\\FER-LANG {
    /* ferret language picker */
    static const char *langs[] = {
	"cs", /*"cy",*/ "da", "de", "en", "es", "fi", "fr",
	"is", "it", "nl", "no", "pl", "pt", "sv",
	NULL
    };
    do_picker('L', langs);
}
\\FER-AD {
    /* ferret advert link (with keywords) */
    int pageid = time(NULL) - 894000000;
    int tag = 7533; /* english */
    if (db_name.length() >= 12) {
	switch (db_name[8]) {
	 case 'r':
	    if (db_name == "ferret.french") tag = 7542;
	    break;
	 case 'e':
	    if (db_name == "ferret.german") tag = 7543;
	    break;
	 case 't':
	    if (db_name == "ferret.italian") tag = 7584;
	    break;
	 case 'p':
	    if (db_name == "ferret.spanish") tag = 7544;
	    break;
	 case 'w':
	    if (db_name == "ferret.swedish") tag = 7545;
	    break;
	}
    }
    cout << "<A HREF=\"http://adforce.imgis.com/"
	    "?adlink|44|" << tag << '|' << pageid << "|1|key="
	 << ad_keywords << "\" TARGET=_top><IMG\n"
	    "SRC=\"http://adforce.imgis.com/"
	    "?adserv|44|" << tag << '|' << pageid << "|1|key="
	 << ad_keywords
	 << "\" BORDER=0 HEIGHT=60 WIDTH=468 NATURALSIZEFLAG=0 "
	    "ALIGN=BOTTOM "
	    "ALT=\"Intelligent access to over 30 million web pages\""
	    "></A>\n";
}
\\FREQS {
#if 0 // FIXME:
    if (!new_terms.empty()) {
	vector<om_termname>::const_iterator i;
	for (i = new_terms.begin(); i != new_terms.end(); i++) {
	    const char *term = i->c_str();

	    int freq = enquire->get_termfreq(*i);
	    
	    if (i == new_terms.begin()) {
		cout << "<B>Individual word frequencies:</B>\n";
	    } else {
		cout << ", ";
	    }
	    if (strchr(term, ' ')) {
		cout << "\"" << term << "\":&nbsp;";
	    } else {
		cout << term << ":&nbsp;";
	    }
	    pretty_printf("%d", &freq);
	}
	if (!new_terms.empty()) cout << "<BR>";
    }
#endif
}
