/* selectpostlist.cc: Parent class for classes which only return selected docs
 *
 * ----START-LICENCE----
 * Copyright 1999,2000,2001 BrightStation PLC
 * Copyright 2002 Ananova Ltd
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

#include <config.h>
#include "selectpostlist.h"

PostList *
SelectPostList::next(om_weight w_min)
{
    DEBUGCALL(MATCH, PostList *, "SelectPostList::next", w_min);
    do {
        PostList *p = source->next(w_min);
	(void)p;
	Assert(p == NULL); // AND should never prune
    } while (!source->at_end() && !test_doc());
    RETURN(NULL);
}

PostList *
SelectPostList::skip_to(om_docid did, om_weight w_min)
{
    DEBUGCALL(MATCH, PostList *, "SelectPostList::skip_to", did << ", " << w_min);
    if (did > get_docid()) {
	PostList *p = source->skip_to(did, w_min);
	(void)p;
	Assert(p == NULL); // AND should never prune
        if (!source->at_end() && !test_doc()) this->next(w_min);
    }
    RETURN(NULL);
}
