#!/usr/bin/env python3
"""
Create target_definition_mc.txt from ALMA-MC summary CSV.

Usage:
  python write_target_definition_mc.py --in "ALMA-MC Mol Clouds - summary.csv" --out target_definition_mc.txt

Behavior:
- Reads CSV, expects columns: cloud,radec,vmin,vmax
- Removes leading 'ICRS' from radec and splits into RA and Dec
- Converts RA from HH:MM:SS.s to 'HHhMMmSS.s's and Dec from D.MM.SS to 'DdMMmSSs'
- Computes velocity center = mean(vmin,vmax)
- Computes velocity width = vmax - vmin
- Writes one line per valid entry: cloud  RA  Dec  vsys  vwidth
"""

import argparse
import csv
import re
import sys


def parse_radec(radec_raw):
    if not radec_raw:
        return None, None
    s = radec_raw.strip()
    # remove the ICRS prefix if present
    s = re.sub(r'(?i)^ICRS\s*', '', s)
    parts = s.split()
    if len(parts) < 2:
        return None, None
    ra_tok = parts[0].strip().strip(',')
    dec_tok = parts[1].strip().strip(',')

    # parse RA (expected H:M:S or H:M:S.s)
    ra_parts = re.split('[:hms HMS]+', ra_tok)
    if len(ra_parts) < 3 or not ra_parts[0]:
        # try colon split
        ra_parts = ra_tok.split(':')
    if len(ra_parts) >= 3:
        h = ra_parts[0]
        m = ra_parts[1]
        sec = ra_parts[2]
    else:
        return None, None
    h = h.zfill(2)
    m = m.zfill(2)
    sec = sec
    # ensure seconds keep decimal if present
    ra_out = f"{h}h{m}m{sec}s"

    # parse Dec: separators may be ':' or '.' or nothing
    dec_tok_clean = dec_tok.replace(':', '.').replace('..', '.')
    # keep sign
    sign = ''
    if dec_tok_clean.startswith('-') or dec_tok_clean.startswith('+'):
        sign = dec_tok_clean[0]
        dec_body = dec_tok_clean[1:]
    else:
        dec_body = dec_tok_clean
    dparts = dec_body.split('.')
    # pad to 3 fields
    if len(dparts) == 1:
        d = dparts[0]
        dm = '00'
        ds = '00'
    elif len(dparts) == 2:
        d = dparts[0]
        dm = dparts[1]
        ds = '00'
    else:
        d, dm, ds = dparts[0], dparts[1], '.'.join(dparts[2:])
    d = d.zfill(2)
    dm = dm.zfill(2)
    ds = ds
    dec_out = f"{sign}{d}d{dm}m{ds}s"

    return ra_out, dec_out


def parse_float(val):
    if val is None:
        return None
    v = str(val).strip()
    if v == '':
        return None
    # Remove any arrows or text like '204->210'
    m = re.match(r"^\s*([+-]?[0-9]+(?:\.[0-9]+)?)", v)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            return None
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--in', dest='infile', required=True, help='Input CSV file')
    parser.add_argument('--out', dest='outfile', required=True, help='Output target_definition_mc.txt')
    args = parser.parse_args()

    try:
        with open(args.infile, newline='') as csvfile:
            reader = csv.DictReader(csvfile)
            rows = list(reader)
    except Exception as e:
        print(f"Error reading input CSV: {e}", file=sys.stderr)
        sys.exit(1)

    out_rows = []
    for r in rows:
        cloud = r.get('cloud') or r.get('Cloud') or r.get('cloud ')
        if cloud is None:
            continue
        cloud = cloud.strip()
        if cloud == '' or cloud.startswith('-'):
            continue
        radec = r.get('radec') or r.get('radec ')
        ra, dec = parse_radec(radec)
        if ra is None or dec is None:
            # skip if no valid radec
            continue
        vmin = parse_float(r.get('vmin'))
        vmax = parse_float(r.get('vmax'))
        if vmin is None or vmax is None:
            # skip rows without both velocities
            continue
        vsys = (vmin + vmax) / 2.0
        vwidth = vmax - vmin
        # format velocities: if integer-valued, write as int
        def fmt_vel(x):
            if abs(x - round(x)) < 1e-6:
                return str(int(round(x)))
            else:
                return f"{x:.3f}"
        out_rows.append((cloud, ra, dec, fmt_vel(vsys), fmt_vel(vwidth)))

    # Prepare header matching target_definitions.txt
    header = '''##########################################################################
# TARGET DEFINITION KEY
##########################################################################

# Key to define the targets in a project.

# In the ms_key each measurement set is mapped to a "target", which
# has an associated position, velocity, and velocity width. These are
# defined in this file. In cases where linear mosaicking is desired,
# this file should also define targets for the combined linear
# mosaics.

# The syntax for the key is space or tab delimited:

# Column 1: target name. This can be anything but needs to be used
# consistently across all of the key files.

# Column 2: phase center r.a. string. Used in imaging.

# Column 3: phase center dec string. Used in imaging.

# Column 4: source velocity [km/s] currently assumes LSRK radio
# convention.

# Column 5: velocity width [km/s] used for imaging and continuum
# subtraction and u-v data staging.

# Note that the phase center isn't the same as the object center. This
# is an importnat distinction mainly in the case of mosaics that cover
# only part of the object (e.g., the PHANGS-ALMA linear mosaic cases).

##########################################################################\n\n'''

    # Determine column widths
    targ_w = 10
    ra_w = 13
    dec_w = 13
    vel_w = 9

    try:
        with open(args.outfile, 'w') as out:
            out.write(header)
            for (cloud, ra, dec, vsys_s, vwidth_s) in out_rows:
                line = f"{cloud:<{targ_w}} {ra:<{ra_w}} {dec:<{dec_w}} {vsys_s:>{vel_w}} {vwidth_s:>{vel_w}}\n"
                out.write(line)
    except Exception as e:
        print(f"Error writing output file: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Wrote {len(out_rows)} entries to {args.outfile}")

if __name__ == '__main__':
    main()
