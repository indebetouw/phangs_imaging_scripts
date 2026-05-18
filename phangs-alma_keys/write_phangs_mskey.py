from astropy.table import Table
import ast


tim2=Table.read("ALMA-MC Mol Clouds - imaging2.tsv", format="csv", delimiter="\t")

#circinus_1     2018.1.01321 	all  7m	  1	2018.1.01321.S/science_goal.uid___A001_X133d_X3c35/group.uid___A001_X133d_X3c36/member.uid___A001_X133d_X3c37/calibrated/uid___A002_Xd845af_Xa5a9.ms

with open("mskeys_mc_12CO21.txt","w") as f:
    # write a fixed-width header (narrower columns)
    f.write(f"{ 'SOURCE':<20}{'PID':<20}{'FIELD':<30}{'ARR':<6}{'OBS':>4} {'MSKEY':<120}\n")
    f.write(f"{'-'*20}{'-'*20}{'-'*30}{'-'*6}{'-'*5} {'-'*120}\n")
    for i in range(len(tim2)):
        if tim2["line"][i] == "12CO21":
            source = tim2["name"][i]
            pid = tim2["PID"][i]
            field = tim2["field"][i]
            mskeys = tim2["vis"][i]
            obsid = 1

            def parse_maybe_list(value, split_on_comma=False):
                raw_value = str(value).strip()
                parsed = []
                try:
                    val = ast.literal_eval(raw_value)
                    if isinstance(val, (list, tuple)):
                        parsed = [str(x) for x in val]
                    else:
                        parsed = [str(val)]
                except Exception:
                    if raw_value.startswith('[') and raw_value.endswith(']'):
                        s = raw_value[1:-1]
                        parsed = [p.strip() for p in s.split(',') if p.strip()!='']
                    elif split_on_comma:
                        parsed = [p.strip() for p in raw_value.split(',') if p.strip()!='']
                    else:
                        parsed = [raw_value]
                    if not parsed:
                        parsed = [raw_value]
                return parsed

            ms_list = parse_maybe_list(mskeys, split_on_comma=True)
            field_list = parse_maybe_list(field, split_on_comma=True)

            pid = str(pid).replace(',', '+').split('+')[0].strip()[:20]
            for idx, mskey in enumerate(ms_list):
                field_value = field_list[idx] if idx < len(field_list) else field_list[0]
                field_value = str(field_value).strip()
                if len(field_value)<1:
                    field_value = 'all'
                # clean leading/trailing brackets and quotes/spaces
                mk = str(mskey).strip()
                if mk.startswith('[') and mk.endswith(']'):
                    mk = mk[1:-1].strip()
                mk = mk.strip().strip('"').strip("'")
                mk = mk[:120]
                if "TM" in mk:
                    array="12m"
                else:
                    array="7m"
                # format: SOURCE(20) PID(20) FIELD(min 30) ARR(6) OBS(4,right) MSKEY(120)
                f.write(f"{source:<20}{pid:<20}{field_value:<30} {array:<6}{obsid:>4} {mk:<120}\n")
                obsid+=1
                