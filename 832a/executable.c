#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "executable.h"
#include "832util.h"


/*	Linked executable.  Linking procedure is as follows:
	* Read object files one by one.
	* Find duplicate symbols, find unresolvable references and garbage-collect unused sections:
		* Start with the first section, take each reference in turn
		* Find target symbols for all references, marking the section containing each reference as "touched".
			* If any references can't be found, throw an error
			* If we encounter a weak symbol at this stage, keep looking for a stronger one.
			* If a strong symbol is declared more than once, throw an error.
			* As each section is touched, recursively repeat the resolution process
			* Store pointers to both the target section and target symbol for each reference.
		* Remove any untouched sections.
	* Sort sections:
		* The first section must remain so
		* ctors and dtors must be collected and sorted
		* BSS sections should come last
		* Need to define virtual symbols at the start and end of the BSS sections, and the ctor/dtor lists
	* Assign preliminary addresses to all sections.
	* Calculate initial size of all sections, along with worst-case slack due to alignment
	* Resolve references.  Reference size in bytes will depend upon the reach/absolute address, so need
	  to support relaxation:
		* Assign an initial best-case and worst-case address to all symbols.
			* For each section, take each symbol in turn, find all references with a cursor position
			  before the symbol's cursor position, and calculate best- and worst-case sizes for them,
         	  based on the general case.
		* Assign initial best- and worst- case addresses to sections (just a convenience for symbol calcs.)
		* Refine the best- and worst-case sizes for references based on the tentative symbol addresses.
		* Re-assign addresses to symbols, using the refined reference sizes.
		* If any references still have differences between best and worst case sizes, repeat the last two steps.
		* (Must limit how many times we do this in case we end up with some kind of oscillation happening.)
	* Assign final addresses to all symbols, taking alignment restrictions into account
	* Re-resolve all references using the symbols' final addresses.
	* Save the linked executable
*/

struct executable *executable_new()
{
	struct executable *result=(struct executable *)malloc(sizeof(struct executable));
	if(result)
	{
		result->objects=0;
		result->lastobject=0;
		result->map=sectionmap_new();
	}
	return(result);
}

void executable_delete(struct executable *exe)
{
	if(exe)
	{
		struct objectfile *obj,*next;
		next=exe->objects;
		while(next)
		{
			obj=next;
			next=obj->next;
			objectfile_delete(obj);
		}
		if(exe->map)
			sectionmap_delete(exe->map);
		free(exe);
	}
}

void executable_loadobject(struct executable *exe,const char *fn)
{
	if(exe)
	{
		struct objectfile *obj=objectfile_new();
		if(exe->lastobject)
			exe->lastobject->next=obj;
		else
			exe->objects=obj;
		exe->lastobject=obj;

		objectfile_load(obj,fn);
	}
}

void executable_dump(struct executable *exe,int untouched)
{
	struct objectfile *obj;
	obj=exe->objects;
	while(obj)
	{
		objectfile_dump(obj,untouched);
		obj=obj->next;
	}
}


/* Hunt for a symbol, but exclude a particular section from the search.
   If a weak symbol is found the search continues for a stronger one.
   If no non-weak version is found, the last version declared will be used.
 */
struct symbol *executable_resolvereference(struct executable *exe,struct symbol *ref,struct section *excludesection)
{
	struct symbol *result=0;
	struct section *sect;
	if(exe)
	{
		/* Check builtin sections first */
		sect=exe->map->builtins;
		while(sect)
		{
			struct symbol *sym=section_findsymbol(sect,ref->identifier);
			if(sym)
			{
/*				ref->sect=sect;*/
				ref->resolve=sym;
				return(sym);
			}
			sect=sect->next;
		}

		struct objectfile *obj=exe->objects;
		while(obj)
		{
			sect=obj->sections;
			while(sect)
			{
				if(sect!=excludesection)
				{
					struct symbol *sym=section_findsymbol(sect,ref->identifier);
					if(sym)
					{
						printf("%s's flags: %x, %x\n",ref->identifier,sym->flags,sym->flags&SYMBOLFLAG_GLOBAL);
						if(sym->flags&SYMBOLFLAG_WEAK)
						{
							printf("Weak symbol found - keep looking\n");
/*							ref->sect=sect;*/
							ref->resolve=sym;
							result=sym; /* Use this result if nothing better is found */
						}
						else if((sym->flags&SYMBOLFLAG_GLOBAL)==0)
						{
							if(excludesection && excludesection->obj == sect->obj)
							{
								printf("Symbol found without global scope, but within the same object file\n");
/*								ref->sect=sect;*/
								ref->resolve=sym;
								return(sym);
							}
							else
								printf("Symbol found but not globally declared - keep looking\n");
						}
						else
						{
/*							ref->sect=sect;*/
							ref->resolve=sym;
							return(sym);
						}
					}
				}
				sect=sect->next;
			}

			obj=obj->next;
		}
	}
	/* Return either zero or the most recently found weak instance */
	return(result);	
}


/* Resolve each reference within a section, recursively repeating the
   process for each section in which a reference was found. */
int executable_resolvereferences(struct executable *exe,struct section *sect)
{
	int result=1;
	struct symbol *ref=sect->refs;
	if(!sect)
		return(0);
	if(sect && (sect->flags&SECTIONFLAG_TOUCHED))
		return(1);
	section_touch(sect);

	while(ref)
	{
		if(!(ref->flags&SYMBOLFLAG_ALIGN)) /* Don't try and resolve an alignment ref */
		{
			struct symbol *sym=section_findsymbol(sect,ref->identifier);
			struct symbol *sym2=0;
			if(sym)
			{
				printf("Found symbol %s within the current section\n",sym->identifier);
/*				ref->sect=sect;	*//* will be overridden if a better match is found */
			}
			if(!sym || (sym->flags&SYMBOLFLAG_WEAK))
			{
				printf("Symbol %s not found (or weak) - searching all sections...\n",ref->identifier);
				sym2=executable_resolvereference(exe,ref,sect);
			}
			if(sym2)
				sym=sym2;
			if(!sym)
			{
				fprintf(stderr,"\n*** %s - unresolved symbol: %s\n\n",sect->obj->filename,ref->identifier);
				result=0;
			}
			ref->resolve=sym;

			/* Recursively resolve references in the section containing the symbol just found. */
			if(sym)
				result&=executable_resolvereferences(exe,ref->resolve->sect);
		}
		ref=ref->next;
	}
	return(result);
}


int executable_resolvecdtors(struct executable *exe)
{
	int result=1;
	int ctorwarn=0;
	if(exe)
	{
		struct objectfile *obj=exe->objects;
		struct section *sect=sectionmap_getbuiltin(exe->map,BUILTIN_CTORS_START);

		/* Throw a warning if we have unreferenced ctors / dtors */
		if(sect && !(sect->flags & SECTIONFLAG_TOUCHED))
			ctorwarn=1;

		while(obj)
		{
			sect=obj->sections;
			while(sect)
			{
				if(!(sect->flags&SECTIONFLAG_TOUCHED))
				{
					if((sect->flags&SECTIONFLAG_CTOR) || (sect->flags&SECTIONFLAG_DTOR))
					{
						result&=executable_resolvereferences(exe,sect);
						if(ctorwarn)
						{
							fprintf(stderr,"\nWARNING: ctors/dtors found but __ctors_start__ not referenced\n\n");
							ctorwarn=0;
						}
					}
				}
				sect=sect->next;
			}
			obj=obj->next;
		}
	}

	return(result);
}


/* 
	Assign an initial best-case and worst-case address to all symbols.
*/

void executable_assignaddresses(struct executable *exe)
{
	int i;
	if(exe && exe->map)
	{
		struct sectionmap *map=exe->map;
		struct section *sect,*prev;
		int j;

		for(j=0;j<3;++j)
		{
			/* Make several passes through the sectionmap.
			   The first pass assigns initial best- and worst-case sizes to all references.
			   With no tentative addresses assigned, the worst-case sizes will be pessimistic.
			   Addresses are then assigned to symbols based on the initial sizes; both are refined
			   in subsequent passes.  */
			for(i=0;i<map->entrycount;++i)
			{
				sect=map->entries[i].sect;
				if(sect)
					section_sizereferences(map->entries[i].sect);
			}

			/* Now assign addresses */
			sect=map->entries[0].sect;
			section_assignaddresses(sect,0);
			for(i=1;i<map->entrycount;++i)
			{
				int best,worst;
				if(sect)
					prev=sect;
				sect=map->entries[i].sect;
				if(sect)
					section_assignaddresses(sect,prev);
			}
		}
	}
}


void executable_save(struct executable *exe,const char *fn)
{
	FILE *f;
	f=fopen(fn,"wb");
	if(f && exe && exe->map)
	{
		int i;
		struct sectionmap *map=exe->map;
		struct section *sect,*prev;

		for(i=0;i<map->entrycount;++i)
		{
			sect=map->entries[i].sect;
			if(sect)
				section_outputexe(sect,f);
		}

		fclose(f);
	}
}


void executable_link(struct executable *exe)
{
	/*	FIXME - Catch redefined global symbols */
	int result=1;
	int sectioncount;
	/* Resolve references starting with the first section */
	if(exe && exe->objects && exe->objects->sections)
		result&=executable_resolvereferences(exe,exe->objects->sections);
	/* Resolve any ctor and dtor sections */
	result&=executable_resolvecdtors(exe);

	if(!result)
	{
		executable_delete(exe);
		exit(1);
	}

	sectionmap_populate(exe);
	sectionmap_dump(exe->map);

	executable_assignaddresses(exe);

	executable_dump(exe,0);
}

