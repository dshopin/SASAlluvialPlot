/*First let's replace all missing values in our variables with 'NA'*/
data heart;
     set sashelp.heart;

     array var Sex BP_Status Chol_Status;
     do over var;
           var=coalescec(var,'NA');
     end;
     dummy=1; /*this variable we'll use for counts in PROC MEANS*/
run;


 
proc means data=heart noprint;
     class Sex BP_Status Chol_Status Status;
 
     /*we are interested in counts for individual variables 
       and combinations of all three (cohorts) only*/
     types Sex BP_Status Chol_Status Status
             Sex*BP_Status*Chol_Status*Status;
 
     var dummy;
     output out=heart n=n;
run;


 
 
data heart;
     set heart;
     if _TYPE_=15 then do;
           plot='band'; /*add variable PLOT for easier separation of data
                        for bars and bands later on*/
 
           /*name each cohort by concatenating all categories*/
           cohort=cats(Sex,BP_Status,Chol_Status, Status);
     end;
     else plot='bar';
 
     /*transposing all variables to make a "long" dataset*/
     array var Sex BP_Status Chol_Status;
     do over var;
           Variable=vname(var);
           Category=var;
           if not missing(var) then output;
     end;
     keep cohort Status Variable Category n plot;
run;
 


proc sort data=heart; by plot Variable Category cohort; run;


 
/*Now we create data required for both plots:
midpoints of barchart segments (to add labels) and upper and lower
limits of bandplots*/
data heart;
     set heart;
     by plot Variable;
 
     /*We won't be able to add category labels to the segments of barchart 
     by means of VBARPARM statement itself, so we'll need to use an additional 
     scatter plot for labels. And for this we need to find a position of 
     a label as a midpoint of barchart segment*/
     if plot='bar' then do;
           if FIRST.Variable then upper=n;
           else upper+n;
           midpoint=upper-n/2;
     end;
 
     /*For the bands we need to define both upper and lower limits*/
     else do;
           if FIRST.Variable then lower=0;
           else lower=upper;
           upper=lower+n;
           n=0;
     end;
run;

proc sgplot data=heart noautolegend;
	band x=Variable upper=upper lower=lower /
            group=cohort
            transparency=0.4
            x2axis
			fillattrs=(color=gray);
	vbarparm category=Variable response=n /
            group=Category
            barwidth=0.3;
	scatter x=Variable y=midpoint / 
            markerchar=Category
            markercharattrs=(size=10);
	x2axis display=none;
run;


/*Now we need to smooth bandplots so that they would meet the bars almost
horizontally, forming an S-curve in between. We can achieve it by using
logit function y=1/(1+exp(-x)) to compute intermediate points for the bandplots
between the bars. Steps:

1) Transform the categorical X-axis into numeric ('BP_status' => 1 etc)

2) Generate points between X-positions of bars (e. g. between 1 and 2 
   we'll generate 99 additional points  1.01,1.02,...;

3) Map them from the current interval (e. g. [1,2]) to a symmetric interval
   [-m,m] where the value of m will affect the "steepness" of the S-curve;

4) Use these new mapped values to calculate new upper and lower limits 
   for the bandplots
*/

 
/*Let's assign order numbers to variables*/
proc sort data=heart; by plot Variable; run;
data heart;
     set heart;
     by plot Variable;
     if FIRST.plot then call missing(varnum_bar, varnum_band);
 
     /*we assign separate columns with variable numbers for bars and bandplots
     to avoid annoing warnings from VBARPARM*/
     if FIRST.Variable and plot='bar' then varnum_bar+1;
     else if FIRST.Variable then varnum_band+1;
run;
 


proc sort data=heart; by cohort varnum_band; run;

data heart;
     set heart;
     by cohort;
     /*join same dataset shifting one row forward to see for each band
      at what Y-position it should meet the next bar*/
     set heart(firstobs=2 keep=upper lower rename=(upper=next_upper lower=next_lower));
     if plot='band' and not LAST.cohort then do;
           m=8; /*by trials and errors 8 looks good*/

          /*creating intermediate points*/
           do varnum_band=varnum_band to varnum_band+0.99 by 0.01; 

                /*mapping from [varnum_band;varnum_band+1] to [-m,m]*/
                varnum_mapped = (varnum_band-floor(varnum_band))*2*m-m; 
 
                /*calculating upper and lower and mapping them back to proper
                 positions on the chart*/
                upper_log=(1/(1+exp(-varnum_mapped))) * (next_upper-upper) + upper;
                lower_log=(1/(1+exp(-varnum_mapped))) * (next_lower-lower) + lower;
                output;
           end;
     end;
     else output;
     drop m next:;
run;
 
/*Also we need to make sure that X-axis shows proper labels - variables' names,
not variables' numbers that we used for curves calculations. We'll do it by 
defining these lables explicitly in XAXIS statement. So we need to extract these lables first
into macro variables*/
proc sql noprint;
     select distinct varnum_bar, cats("'",Variable,"'") 
          into :values separated by ' ', :labels separated by ' '
     from heart
     where plot='bar'
     order by varnum_bar
     ;
quit;
 
 
/*Smoothed plot*/
ods graphics / height=1200 width=2000;

proc sgplot data=heart noautolegend;
     band x=varnum_band upper=upper_log lower=lower_log / 
                group=cohort
                transparency=0.4 
                x2axis
                fillattrs=(color=gray);
     vbarparm category=varnum_bar response=n /
                group=Category
                barwidth=0.3;
     scatter x=varnum_bar y=midpoint /
                markerchar=Category
                markercharattrs=(size=10)
;
     x2axis display=none;
     xaxis values=(&values) valuesdisplay=(&labels) label='Variable';
run;




/*Colouring cohorts based on vital status - Dead or Alive*/

proc sort data=heart out=myattrmap_band(keep=cohort Status) nodupkey;
	where plot='band';
	by cohort Status;
run;

data myattrmap_band;
	length ID FillColor LineColor $10 Value $50;
	set myattrmap_band;
	ID='bandAttr';
	Value=cohort;
	FillColor=ifc(Status='Dead','red','green');
	LineColor=FillColor;
	drop cohort Status;
run;


proc sgplot data=heart	dattrmap=myattrmap_band noautolegend;
	band x=varnum_band upper=upper_log lower=lower_log /
              group=cohort
              transparency=0.4
              x2axis
		      attrid=bandAttr;
	vbarparm category=varnum_bar response=n /
              group=Category
              barwidth=0.3;
	scatter x=varnum_bar y=midpoint /
              markerchar=Category
              markercharattrs=(size=10);
	x2axis display=none;
	xaxis values=(&values) valuesdisplay=(&labels) label='Variable';
run;




/*Now let's make every bar one color with categories having different lightness*/

/*Extract default colours from SAS template*/
data heart;
	set heart;
	VarCategory=cats(Variable, Category);
run;
proc template;
   source styles.default /file='style.tmp';
run;
data colors;
   infile 'style.tmp';
   input;
   if index(_infile_, 'gdata') then do;
      element = scan(_infile_, 1, ' ');
      Color = scan(_infile_, 3, ' ;');
      varnum_bar = input(compress(element, 'gdat'';'), ?? 2.);
      if varnum_bar then output;
   end;
   drop element;
run;
%COLORMAC

data _null_;
	set colors end=eof;
	if _N_=1 then call execute("data colors;");
	call execute("	varnum_bar="||varnum_bar||";");
	call execute(cats('	Color="',Color,'";'));
	call execute(cats('HLS="%RGB2HLS(',Color,')";'));
	call execute("	output;");
	if eof then call execute("run;");
run;

proc sort data=colors; by varnum_bar; run;
proc sort data=heart out=myattrmap_bar(keep=varnum_bar VarCategory) nodupkey;
	where plot='bar';
	by varnum_bar VarCategory;
run;

data myattrmap_bar;
	merge myattrmap_bar(in=inM) colors;
	by varnum_bar;
	if inM;
run;

/*creating gradients within one variable*/
data myattrmap_bar;
	length ID FillColor LineColor $10 Value $50;
	do _N_=1 by 1 until(LAST.varnum_bar);
		set myattrmap_bar;
		by varnum_bar;
		count+1;
		if FIRST.varnum_bar then count=1;
	end;
	do _N_=1 by 1 until(LAST.varnum_bar);
		set myattrmap_bar;
		by varnum_bar;
		lightness+floor((200-80)/(count-1));
		if FIRST.varnum_bar then lightness=80;
		ID='barAttr';
		FillColor=HLS;
		substr(FillColor,5,2)=put(lightness,hex2.);
		LineColor=FillColor;
		Value=VarCategory;
		output;
	end;
;
run;

data myattrmap;
	set myattrmap_bar(keep=ID FillColor LineColor Value)
		myattrmap_band(keep=ID FillColor LineColor Value);
run;

proc sgplot data=heart	dattrmap=myattrmap noautolegend;
	band x=varnum_band upper=upper_log lower=lower_log / group=cohort transparency=0.4 x2axis attrid=bandAttr;
	vbarparm category=varnum_bar response=n / group=VarCategory barwidth=0.3  
				attrid=barAttr;
	scatter x=varnum_bar y=midpoint / markerchar=Category markercharattrs=(size=10);
	x2axis display=none;
	xaxis values=(&values) valuesdisplay=(&labels) label='Variable';
run;


