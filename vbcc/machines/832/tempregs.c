/*
To do: 
  Peephole optimise away such constructs as mr r0, mt r0
  | Optimise addresses of stack variables - lea's can mostly be replaced with simple adds.
  Detect absolute moves to reg, prune any that aren't needed.

*/

zmax val2zmax(FILE *f,struct obj *o,int t)
{
  union atyps *p=&o->val;
  t&=NU;
  if(t==CHAR) return(zc2zm(p->vchar));
  if(t==(UNSIGNED|CHAR)) return(zuc2zum(p->vuchar));
  if(t==SHORT) return(zs2zm(p->vshort));
  if(t==(UNSIGNED|SHORT)) return(zus2zum(p->vushort));

  /*
  if(t==FLOAT) return(zf2zld(p->vfloat);emitzld(f,vldouble);}
  if(t==DOUBLE){vldouble=zd2zld(p->vdouble);emitzld(f,vldouble);}
  if(t==LDOUBLE){emitzld(f,p->vldouble);}
  */

  if(t==INT) return(zi2zm(p->vint));
  if(t==(UNSIGNED|INT)) return(zui2zum(p->vuint));
  if(t==LONG) return(zl2zm(p->vlong));
  if(t==(UNSIGNED|LONG)) return(zul2zum(p->vulong));
  if(t==LLONG) return(zll2zm(p->vllong));
  if(t==(UNSIGNED|LLONG)) return(zull2zum(p->vullong));
  if(t==MAXINT) return(p->vmax);
  if(t==(UNSIGNED|MAXINT)) return(p->vumax);
  if(t==POINTER) return(zul2zum(p->vulong));
  emit(f,"#FIXME - no float support yet\n");
}


static void emit_pcreltotemp(FILE *f,char *lab,int suffix)
{
  emit(f,"pcrel\n");
  emit(f,"\tli\t2\n"); // Assuming 16 bits will be enough for offset.
  emit(f,"\t.byte\tIMW0(PCREL(%s%d)-1)\n",lab,suffix);
  emit(f,"\t.byte\tIMW1(PCREL(%s%d)-0)\n",lab,suffix); // Let's go little-endian for now.
}


static void emit_externtotemp(FILE *f,char *lab)
{
//  emit(f,"#FIXME extern not yet supported\n");
  // extern support is either going to mean redefining how the li instruction works
  // so that it specifies that the following n bytes should be interpreted as
  // immediate data, or tracking the number of bytes output so we can use
  // a construct such as
  // .align 4
  // <unrelated op 1>
  // <unrelated op 2>
  // <unrelated op 3>  - maybe no-ops (cond EX)
  // ldinc r7
  // .int _label // guarantees alignment for _label.  assembler doesn't care but we'd prefer not to implement unaligned loads.
  // Alternatively we could create a label table that we can access in pcrel mode.

  // Experiment with new li format:
  emit(f,"\tli\t4\n"); // Assuming 16 bits will be enough for offset.
  emit(f,"\t.int\t%s\n",lab);
}


static void emit_statictotemp(FILE *f,char *lab,int suffix)
{
  emit(f,"#static\n");
  emit(f,"\tli\t4\n"); // Assuming 16 bits will be enough for offset.
  emit(f,"\t.int\t%s%d\n",lab,suffix);
}


static void emit_constanttotemp(FILE *f,zmax v)
{
  int chunk=1;
  // FIXME - simple single-byte cases:
  zmax v2=v;

  switch(v)
  {
    case 0:
      emit(f,"\tli\t0\n");
      break;

    case 1:
      emit(f,"\tli\t5 # embedded 1\n");
      break;

    case 2:
      emit(f,"\tli\t6 # embedded 2\n");
      break;

    case 0xffffffff:
      emit(f,"\tli\t8 # embedded -1\n");
      break;

    case 4:
      emit(f,"\tliq\t1 # embedded 4\n");
      break;

    case 8:
      emit(f,"\tliq\t2 # embedded 8\n");
      break;

    case 12:
      emit(f,"\tliq\t3 # embedded 12\n");
      break;

    case 16:
      emit(f,"\tliq\t0 # embedded 16\n");
      break;

    case -4:
      emit(f,"\tliq\t7 # embedded -4\n");
      break;

    case -8:
      emit(f,"\tliq\t6 # embedded -8\n");
      break;

    case -12:
      emit(f,"\tliq\t5 # embedded -12\n");
      break;

    case -16:
      emit(f,"\tliq\t4 # embedded -16\n");
      break;

    default:
      while(((v2&0xffffff80)!=0) && ((v2&0xffffff80)!=0xffffff80)) // Are we looking at a sign-extended 8-bit value yet?
      {
        v2>>=8;
        ++chunk;
      }
  
      emit(f,"\tli\t%d; # 0x%x\n",chunk,v);
      while(chunk--) // Do we need to emit the top two bits?
      {
        emit(f,"\t.byte\t%d\n",v&255);
        v>>=8;
      }
      break;
  }
}


/* prepares a register to point to an object, in preparation for a load, store or move */

static void emit_prepobj(FILE *f,struct obj *p,int t,int reg)
{
  emit(f,"\t\t\t\t\t# (prepobj %s)",regnames[reg]);
  if(p->am){
    emit(f,"# FIXME - extended addressing modes not supported\n");
    return;
  }
  if((p->flags&(KONST|DREFOBJ))==(KONST|DREFOBJ)){
    emit(f," const/deref\n");
    emit_constanttotemp(f,val2zmax(f,p,p->dtyp));
    emit(f,"\tmr\t%s\n",regnames[t1]);
    reg_stackrel[reg]=0;
    return;
  }

  if(p->flags&DREFOBJ)
  {
    emit(f," deref ");
    /* Dereferencing a pointer */
    if(p->flags&REG){
      emit(f," reg - no need to prep\n");
//      emit(f,"\n\tld\t%s\n",regnames[p->reg]);
    }
    else if(p->flags&VAR) {  // FIXME - figure out what dereferencing means in these contexts
      emit(f," var FIXME - deref?");
      if(p->v->storage_class==AUTO||p->v->storage_class==REGISTER){
        emit(f," reg \n");
	emit_constanttotemp(f,real_offset(p));

        emit(f,"\taddt\t%s\n\texg\t%s\n\tmr\t%s\n",
		regnames[sp],regnames[sp],regnames[reg]);
        reg_stackrel[reg]=0; // Not sure this is correct enough to risk it here.
      }

      else{
        if(!zmeqto(l2zm(0L),p->val.vmax)){
          emit(f," offset ");
          emit_constanttotemp(f,val2zmax(f,p,LONG));
          emit(f,"\tmr\t%s\n",regnames[reg]);
          emit_pcreltotemp(f,labprefix,zm2l(p->v->offset));
          emit(f,"\tadd\t%s\n",regnames[reg]);
        }
        if(p->v->storage_class==STATIC){
          emit_pcreltotemp(f,labprefix,zm2l(p->v->offset));
          emit(f,"\tmr\t%s\n",regnames[reg]);
        }else{
          emit_externtotemp(f,p->v->identifier);
          emit(f,"\tmr\t%s\n",regnames[reg]);
        }
        reg_stackrel[reg]=0;
      }
    }
  }
  else
  {

    if(p->flags&REG){
      emit(f," reg %s - no need to prep\n",regnames[p->reg]);

    }else if(p->flags&VAR) {
      if(p->v->storage_class==AUTO||p->v->storage_class==REGISTER)
      {
        /* Set a register to point to a stack-base variable. */
        emit(f," var, auto|reg\n");  if(p->v->storage_class==REGISTER) emit(f,"# (is actually REGISTER)\n");
        if(real_offset(p)==0)  /* No offset? Just copy the stack pointer */
        {
          emit(f,"\tmt\t%s\n\tmr\t%s\n",regnames[sp],regnames[reg]);
          reg_stackrel[reg]=1;
          reg_stackoffset[reg]=0;
        }
        else if(reg_stackrel[reg])
        {
          if(real_offset(p)-reg_stackoffset[reg])
          {
            emit_constanttotemp(f,real_offset(p)-reg_stackoffset[reg]);
            emit(f,"\tadd\t%s # adjust offset to %d\n",regnames[reg],real_offset(p));
            reg_stackoffset[reg]=real_offset(p);
          }
          else
            emit(f,"\t\t  # %s offset unchanged\n",regnames[reg]);
        }
        else
        {
          emit_constanttotemp(f,real_offset(p));
          emit(f,"\taddt\t%s\n\texg\t%s\n\tmr\t%s\n\n",
            regnames[sp],regnames[sp],regnames[reg]);
          reg_stackrel[reg]=1;
          reg_stackoffset[reg]=real_offset(p);
        }
      }
      else{
        if(!zmeqto(l2zm(0L),p->val.vmax)){
          emit(f," offset ");
          emit_constanttotemp(f,val2zmax(f,p,LONG));
          emit(f,"\tmr\t%s\n",regnames[reg]);
          emit_pcreltotemp(f,labprefix,zm2l(p->v->offset));
          emit(f,"\tadd\t%s\n",regnames[reg]);
        }
        if(p->v->storage_class==STATIC){
          emit_pcreltotemp(f,labprefix,zm2l(p->v->offset));
          emit(f,"\tmr\t%s\n",regnames[reg]);
        }else{
          emit_externtotemp(f,p->v->identifier);
          emit(f,"\tmr\t%s\n",regnames[reg]);
        }
        reg_stackrel[reg]=0;
      }
    }
  }
//  if(p->flags&KONST){
//    emit_constanttotemp(f,val2zmax(f,p,t));
//  }
}


static void emit_objtotemp(FILE *f,struct obj *p,int t)
{
  emit(f,"\t\t\t\t\t# (objtotemp)");
  if(p->am){
    emit(f,"# FIXME - extended addressing modes not supported\n");
    return;
  }
  if((p->flags&(KONST|DREFOBJ))==(KONST|DREFOBJ)){
    emit(f," const/deref # FIXME deal with different data sizes when dereferencing\n");
    emit_prepobj(f,p,t,t1);
    emit(f,"\tld\t%s\n",regnames[t1]);
    return;
  }

  if(p->flags&DREFOBJ)
  {
    emit(f," deref \n");
    /* Dereferencing a pointer */
    if(p->flags&REG){
      emit(f,"\tld\t%s\n",regnames[p->reg]);
    }
    else {
      emit_prepobj(f,p,t,t1);
      emit(f,"\tld\t%s\n",regnames[t1]);
    }
  }
  else
  {
    if(p->flags&REG){
      emit(f," reg %s\n",regnames[p->reg]);
      emit(f,"\tmt\t%s\n",regnames[p->reg]);
    }else if(p->flags&VAR) {
      if(p->v->storage_class==AUTO||p->v->storage_class==REGISTER)
      {
        emit(f," var, auto|reg\n");
        emit_prepobj(f,p,t,t1);
        emit(f,"\tld\t%s\n",regnames[t1]);
//	emit(f,"\tli\tIMW0(%ld)\n\taddt\t%s\n\texg\t%s\n\tmr\t%s\n\tld\t%s\n",
//		real_offset(p),regnames[sp],regnames[sp],regnames[t1],regnames[t1]);
      }
      else{
        if(!zmeqto(l2zm(0L),p->val.vmax)){
          emit(f," offset ");
          emit_constanttotemp(f,val2zmax(f,p,LONG));
          emit(f,"\tmr\t%s\n",regnames[t1]);
          emit_pcreltotemp(f,labprefix,zm2l(p->v->offset));
          emit(f,"\tadd\t%s\n",regnames[t1]);
          reg_stackrel[t1]=0;
        }
        if(p->v->storage_class==STATIC){
          emit(f,"# static\n");
          // FIXME - not pc-relative!
//          emit_pcreltotemp(f,labprefix,zm2l(p->v->offset));
          emit_statictotemp(f,labprefix,zm2l(p->v->offset));
        }else{
          emit(f,"storage class %d\n",p->v->storage_class);
          emit_externtotemp(f,p->v->identifier);
        }
      }
    }
    else if(p->flags&KONST){
      emit(f," const\n");
      emit_constanttotemp(f,val2zmax(f,p,t));
    }
    else {
      emit(f," unknown type %d\n",p->flags);
    }
  }
}


