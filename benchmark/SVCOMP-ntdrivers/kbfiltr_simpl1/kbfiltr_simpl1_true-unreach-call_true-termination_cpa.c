//extern void __VERIFIER_error() __attribute__ ((__noreturn__));

//extern char __VERIFIER_nondet_char(void);
extern int __VERIFIER_nondet_int(void);
//extern long __VERIFIER_nondet_long(void);
//extern void *__VERIFIER_nondet_pointer(void);
//extern int __VERIFIER_nondet_int();
int KbFilter_PnP(int DeviceObject , int Irp );
int IofCallDriver(int DeviceObject , int Irp );
int KeSetEvent(int Event , int Increment , int Wait );
int KeWaitForSingleObject(int Object , int WaitReason , int WaitMode , int Alertable ,
                          int Timeout );
int KbFilter_Complete(int DeviceObject , int Irp , int Context );
/* Generated by CIL v. 1.3.6 */
/* print_CIL_Input is true */

int KernelMode  ;
int Executive  ;
int s  ;
int UNLOADED  ;
int NP  ;
int DC  ;
int SKIP1  ;
int SKIP2  ;
int MPR1  ;
int MPR3  ;
int IPC  ;
int pended  ;
int compFptr  ;
int compRegistered  ;
int lowerDriverReturn  ;
int setEventCalled  ;
int customIrp  ;
int myStatus  ;

void stub_driver_init(void) 
{ 

  {
  s = NP;
  pended = 0;
  compFptr = 0;
  compRegistered = 0;
  lowerDriverReturn = 0;
  setEventCalled = 0;
  customIrp = 0;
  return;
}
}
void _BLAST_init(void) 
{ 

  {
  UNLOADED = 0;
  NP = 1;
  DC = 2;
  SKIP1 = 3;
  SKIP2 = 4;
  MPR1 = 5;
  MPR3 = 6;
  IPC = 7;
  s = UNLOADED;
  pended = 0;
  compFptr = 0;
  compRegistered = 0;
  lowerDriverReturn = 0;
  setEventCalled = 0;
  customIrp = 0;
  return;
}
}
void IofCompleteRequest(int, int);
void errorFn(void);
int KbFilter_PnP(int DeviceObject , int Irp ) 
{ int devExt ;
  int irpStack ;
  int status ;
  int event = __VERIFIER_nondet_int() ;
  int DeviceObject__DeviceExtension = __VERIFIER_nondet_int() ;
  int Irp__Tail__Overlay__CurrentStackLocation = __VERIFIER_nondet_int() ;
  int irpStack__MinorFunction = __VERIFIER_nondet_int() ;
  int devExt__TopOfStack = __VERIFIER_nondet_int() ;
  int devExt__Started ;
  int devExt__Removed ;
  int devExt__SurpriseRemoved ;
  int Irp__IoStatus__Status ;
  int Irp__IoStatus__Information ;
  int Irp__CurrentLocation = __VERIFIER_nondet_int() ;
  int irpSp ;
  int nextIrpSp ;
  int nextIrpSp__Control ;
  int irpSp___0 ;
  int irpSp__Context ;
  int irpSp__Control ;
  long __cil_tmp23 ;

  {
  status = 0;
  devExt = DeviceObject__DeviceExtension;
  irpStack = Irp__Tail__Overlay__CurrentStackLocation;
  if (irpStack__MinorFunction == 0) {
    goto switch_0_0;
  } else {
    if (irpStack__MinorFunction == 23) {
      goto switch_0_23;
    } else {
      if (irpStack__MinorFunction == 2) {
        goto switch_0_2;
      } else {
        if (irpStack__MinorFunction == 1) {
          goto switch_0_1;
        } else {
          if (irpStack__MinorFunction == 5) {
            goto switch_0_1;
          } else {
            if (irpStack__MinorFunction == 3) {
              goto switch_0_1;
            } else {
              if (irpStack__MinorFunction == 6) {
                goto switch_0_1;
              } else {
                if (irpStack__MinorFunction == 13) {
                  goto switch_0_1;
                } else {
                  if (irpStack__MinorFunction == 4) {
                    goto switch_0_1;
                  } else {
                    if (irpStack__MinorFunction == 7) {
                      goto switch_0_1;
                    } else {
                      if (irpStack__MinorFunction == 8) {
                        goto switch_0_1;
                      } else {
                        if (irpStack__MinorFunction == 9) {
                          goto switch_0_1;
                        } else {
                          if (irpStack__MinorFunction == 12) {
                            goto switch_0_1;
                          } else {
                            if (irpStack__MinorFunction == 10) {
                              goto switch_0_1;
                            } else {
                              if (irpStack__MinorFunction == 11) {
                                goto switch_0_1;
                              } else {
                                if (irpStack__MinorFunction == 15) {
                                  goto switch_0_1;
                                } else {
                                  if (irpStack__MinorFunction == 16) {
                                    goto switch_0_1;
                                  } else {
                                    if (irpStack__MinorFunction == 17) {
                                      goto switch_0_1;
                                    } else {
                                      if (irpStack__MinorFunction == 18) {
                                        goto switch_0_1;
                                      } else {
                                        if (irpStack__MinorFunction == 19) {
                                          goto switch_0_1;
                                        } else {
                                          if (irpStack__MinorFunction == 20) {
                                            goto switch_0_1;
                                          } else {
                                            goto switch_0_1;
                                            if (0) {
                                              switch_0_0: 
                                              irpSp = Irp__Tail__Overlay__CurrentStackLocation;
                                              nextIrpSp = Irp__Tail__Overlay__CurrentStackLocation - 1;
                                              nextIrpSp__Control = 0;
                                              if (s != NP) {
                                                {
                                                errorFn();
                                                }
                                              } else {
                                                if (compRegistered != 0) {
                                                  {
                                                  errorFn();
                                                  }
                                                } else {
                                                  compRegistered = 1;
                                                }
                                              }
                                              {
                                              irpSp___0 = Irp__Tail__Overlay__CurrentStackLocation - 1;
                                              irpSp__Control = 224;
                                              status = IofCallDriver(devExt__TopOfStack,
                                                                     Irp);
                                              }
                                              {
                                              __cil_tmp23 = (long )status;
                                              if (__cil_tmp23 == 259 ) {
                                                {
                                                KeWaitForSingleObject(event, Executive,
                                                                      KernelMode,
                                                                      0, 0);
                                                }
                                              }
                                              }
                                              if (status >= 0) {
                                                if (myStatus >= 0) {
                                                  devExt__Started = 1;
                                                  devExt__Removed = 0;
                                                  devExt__SurpriseRemoved = 0;
                                                }
                                              }
                                              {
                                              Irp__IoStatus__Status = status;
                                              myStatus = status;
                                              Irp__IoStatus__Information = 0;
                                              IofCompleteRequest(Irp, 0);
                                              }
                                              goto switch_0_break;
                                              switch_0_23: 
                                              devExt__SurpriseRemoved = 1;
                                              if (s == NP) {
                                                s = SKIP1;
                                              } else {
                                                {
                                                errorFn();
                                                }
                                              }
                                              {
                                              Irp__CurrentLocation ++;
                                              Irp__Tail__Overlay__CurrentStackLocation ++;
                                              status = IofCallDriver(devExt__TopOfStack,
                                                                     Irp);
                                              }
                                              goto switch_0_break;
                                              switch_0_2: 
                                              devExt__Removed = 1;
                                              if (s == NP) {
                                                s = SKIP1;
                                              } else {
                                                {
                                                errorFn();
                                                }
                                              }
                                              {
                                              Irp__CurrentLocation ++;
                                              Irp__Tail__Overlay__CurrentStackLocation ++;
                                              IofCallDriver(devExt__TopOfStack, Irp);
                                              status = 0;
                                              }
                                              goto switch_0_break;
                                              switch_0_1: ;
                                              if (s == NP) {
                                                s = SKIP1;
                                              } else {
                                                {
                                                errorFn();
                                                }
                                              }
                                              {
                                              Irp__CurrentLocation ++;
                                              Irp__Tail__Overlay__CurrentStackLocation ++;
                                              status = IofCallDriver(devExt__TopOfStack,
                                                                     Irp);
                                              }
                                              goto switch_0_break;
                                            } else {
                                              switch_0_break: ;
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  return (status);
}
}
int test_main(void)  // "test_main"
{ int status ;
  int irp = __VERIFIER_nondet_int() ;
  int pirp ;
  int pirp__IoStatus__Status ;
  int irp_choice = __VERIFIER_nondet_int() ;
  int devobj = __VERIFIER_nondet_int() ;
  int __cil_tmp8 ;

  {
  {
;
KernelMode = 0 ;
 Executive  = 0;
s  = 0;
UNLOADED  = 0;
NP  = 0;
 DC  = 0;
 SKIP1  = 0;
 SKIP2  = 0;
 MPR1  = 0;
 MPR3  = 0;
 IPC  = 0;
 pended  = 0;
 compFptr  = 0;
 compRegistered  = 0;
 lowerDriverReturn  = 0;
 setEventCalled  = 0;
 customIrp  = 0;
 myStatus  = 0;

  status = 0;
  pirp = irp;
  _BLAST_init();
  }
  if (status >= 0) {
    s = NP;
    customIrp = 0;
    setEventCalled = customIrp;
    lowerDriverReturn = setEventCalled;
    compRegistered = lowerDriverReturn;
    pended = compRegistered;
    pirp__IoStatus__Status = 0;
    myStatus = 0;
    if (irp_choice == 0) {
      pirp__IoStatus__Status = -1073741637;
      myStatus = -1073741637;
    }
    {
    stub_driver_init();
    }
    {
    if(status >= 0){
      __cil_tmp8 = 1;
    }
    else{
      __cil_tmp8 = 0;
    } 
    if (! __cil_tmp8) {
      return (-1);
    }
    }
    int tmp_ndt_1;
    tmp_ndt_1 = __VERIFIER_nondet_int();
    if (tmp_ndt_1 == 3) {
      goto switch_1_3;
    } else {
      goto switch_1_default;
      if (0) {
        switch_1_3: 
        {
        status = KbFilter_PnP(devobj, pirp);
        }
        goto switch_1_break;
        switch_1_default: ;
        return (-1);
      } else {
        switch_1_break: ;
      }
    }
  }
  if (pended == 1) {
    if (s == NP) {
      s = NP;
    } else {
      goto _L___2;
    }
  } else {
    _L___2: 
    if (pended == 1) {
      if (s == MPR3) {
        s = MPR3;
      } else {
        goto _L___1;
      }
    } else {
      _L___1: 
      if (s != UNLOADED) {
        if (status != -1) {
          if (s != SKIP2) {
            if (s != IPC) {
              if (s == DC) {
                goto _L___0;
              }
            } else {
              goto _L___0;
            }
          } else {
            _L___0: 
            if (pended == 1) {
              if (status != 259) {
                {
                errorFn();
                }
              }
            } else {
              if (s == DC) {
                if (status == 259) {

                }
              } else {
                if (status != lowerDriverReturn) {

                }
              }
            }
          }
        }
      }
    }
  }

  return (status);
}
}
void stubMoreProcessingRequired(void) 
{ 

  {
  if (s == NP) {
    s = MPR1;
  } else {
    {
    errorFn();
    }
  }
  return;
}
}
int IofCallDriver(int DeviceObject , int Irp ) 
{
  int returnVal2 ;
  int compRetStatus ;
  int lcontext = __VERIFIER_nondet_int() ;
  long long __cil_tmp7 ;
;
  {
  if (compRegistered) {
    compRetStatus = KbFilter_Complete(DeviceObject, Irp, lcontext);
    stubMoreProcessingRequired();
  }
  int tmp_ndt_2;
  tmp_ndt_2 = __VERIFIER_nondet_int();
  if (tmp_ndt_2 == 0) {
    goto switch_2_0;
  } else {
    int tmp_ndt_3;
    tmp_ndt_3 = __VERIFIER_nondet_int();
    if (tmp_ndt_3 == 1) {
      goto switch_2_1;
    } else {
      goto switch_2_default;
      if (0) {
        switch_2_0: 
        returnVal2 = 0;
        goto switch_2_break;
        switch_2_1: 
        returnVal2 = -1073741823;
        goto switch_2_break;
        switch_2_default: 
        returnVal2 = 259;
        goto switch_2_break;
      } else {
        switch_2_break: ;
      }
    }
  }
  if (s == NP) {
    s = IPC;
    lowerDriverReturn = returnVal2;
  } else {
    if (s == MPR1) {
      if (returnVal2 == 259) {
        s = MPR3;
        lowerDriverReturn = returnVal2;
      } else {
        s = NP;
        lowerDriverReturn = returnVal2;
      }
    } else {
      if (s == SKIP1) {
        s = SKIP2;
        lowerDriverReturn = returnVal2;
      } else {
        {
        errorFn();
        }
      }
    }
  }
  return (returnVal2);
}
}
void IofCompleteRequest(int Irp , int PriorityBoost ) 
{ 

  {
  if (s == NP) {
    s = DC;
  } else {
    {
    errorFn();
    }
  }
  return;
}
}
int KeSetEvent(int Event , int Increment , int Wait ) 
{ int l = __VERIFIER_nondet_int() ;

  {
  setEventCalled = 1;
  return (l);
}
}
int KeWaitForSingleObject(int Object , int WaitReason , int WaitMode , int Alertable ,
                          int Timeout ) 
{
;
  {
  if (s == MPR3) {
    if (setEventCalled == 1) {
      s = NP;
      setEventCalled = 0;
    } else {
      goto _L;
    }
  } else {
    _L: 
    if (customIrp == 1) {
      s = NP;
      customIrp = 0;
    } else {
      if (s == MPR3) {
        {
        errorFn();
        }
      }
    }
  }
  int tmp_ndt_4;
  tmp_ndt_4 = __VERIFIER_nondet_int();
  if (tmp_ndt_4 == 0) {
    goto switch_3_0;
  } else {
    goto switch_3_default;
    if (0) {
      switch_3_0: 
      return (0);
      switch_3_default: ;
      return (-1073741823);
    } else {

    }
  }
}
}
int KbFilter_Complete(int DeviceObject , int Irp , int Context ) 
{ int event ;

  {
  {
  event = Context;
  KeSetEvent(event, 0, 0);
  }
  return (-1073741802);
}
}

void errorFn(void) 
{ 

  {
  //ERROR: __VERIFIER_error();
  return;
}
}
