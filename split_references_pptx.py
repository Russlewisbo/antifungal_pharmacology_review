#!/usr/bin/env python3
"""Quarto post-render step: spread the References slide of the pptx over several slides.

Pandoc builds the bibliography after filters run, so it ends up as one overflowing slide.
This script rewrites _output/index.pptx in place using only the standard library.
It is idempotent: a pptx that already has "References (cont.)" slides is left alone.
"""
import re
import sys
import zipfile
from pathlib import Path

PPTX = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("_output/index.pptx")
MAX_REFS_PER_SLIDE = 16
CHAR_BUDGET = 2450  # characters of reference text per slide at 10 pt
FONT_SZ = "1000"  # 10 pt

SLIDE_CT = "application/vnd.openxmlformats-officedocument.presentationml.slide+xml"
SLIDE_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"


def main() -> None:
    if not PPTX.exists():
        return
    with zipfile.ZipFile(PPTX) as z:
        files = {n: z.read(n) for n in z.namelist()}
        order = z.namelist()

    text_files = {n: files[n].decode("utf-8") for n in files
                  if n.endswith(".xml") or n.endswith(".rels")}

    if any("<a:t>References (cont.)</a:t>" in s for n, s in text_files.items()
           if n.startswith("ppt/slides/slide")):
        print("pptx references already split")
        return

    ref_slide = None
    for n in sorted(text_files, key=lambda x: int(re.findall(r"\d+", x)[-1]) if x.startswith("ppt/slides/slide") else -1):
        if n.startswith("ppt/slides/slide") and n.endswith(".xml") and "<a:t>References</a:t>" in text_files[n]:
            ref_slide = n
    if ref_slide is None:
        print("no References slide found")
        return

    xml = text_files[ref_slide]
    # body placeholder text body
    m = re.search(r'(<p:ph idx="1" />.*?<p:txBody><a:bodyPr />\s*<a:lstStyle />)(.*?)(</p:txBody>)', xml, re.S)
    if not m:
        print("could not locate the body placeholder")
        return
    head, body, tail = m.group(1), m.group(2), m.group(3)
    paras = re.findall(r"<a:p>.*?</a:p>", body, re.S)
    def plain(p: str) -> int:
        return len("".join(re.findall(r"<a:t>(.*?)</a:t>", p, re.S)))

    chunks, cur, cur_c = [], [], 0
    for p in paras:
        c = plain(p)
        if cur and (cur_c + c > CHAR_BUDGET or len(cur) >= MAX_REFS_PER_SLIDE):
            chunks.append(cur)
            cur, cur_c = [], 0
        cur.append(p)
        cur_c += c
    if cur:
        chunks.append(cur)
    if len(chunks) < 2:
        return

    def shrink(p: str) -> str:
        return re.sub(r"<a:rPr(?=[ />])", f'<a:rPr sz="{FONT_SZ}"', p)

    rels_name = ref_slide.replace("ppt/slides/", "ppt/slides/_rels/") + ".rels"
    rels = text_files[rels_name]
    rel_items = re.findall(r"<Relationship [^>]*/>", rels)

    def rels_for(chunk_xml: str) -> str:
        used = set(re.findall(r'r:id="(rId\d+)"', chunk_xml))
        keep = [r for r in rel_items
                if "slideLayout" in r or re.search(r'Id="(rId\d+)"', r).group(1) in used]
        return ('<?xml version="1.0" encoding="UTF-8"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                + "".join(keep) + "</Relationships>")

    next_no = max(int(re.findall(r"slide(\d+)\.xml", n)[0]) for n in files
                  if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)) + 1

    pres = text_files["ppt/presentation.xml"]
    pres_rels = text_files["ppt/_rels/presentation.xml.rels"]
    ctypes = text_files["[Content_Types].xml"]

    ref_basename = ref_slide.split("/")[-1]
    ref_rid = re.search(r'Id="(rId\d+)"[^>]*Target="slides/%s"' % re.escape(ref_basename), pres_rels)
    if ref_rid is None:
        ref_rid = re.search(r'Target="slides/%s"[^>]*Id="(rId\d+)"' % re.escape(ref_basename), pres_rels)
    ref_rid = ref_rid.group(1)
    max_sld_id = max(int(i) for i in re.findall(r'<p:sldId id="(\d+)"', pres))
    max_rid = max(int(i) for i in re.findall(r'Id="rId(\d+)"', pres_rels))

    new_entries = []
    for idx, chunk in enumerate(chunks):
        chunk_xml = "".join(shrink(p) for p in chunk)
        slide_xml = xml.replace(m.group(0), head + chunk_xml + tail)
        if idx > 0:
            slide_xml = slide_xml.replace("<a:t>References</a:t>", "<a:t>References (cont.)</a:t>", 1)
        if idx == 0:
            text_files[ref_slide] = slide_xml
            text_files[rels_name] = rels_for(chunk_xml)
            continue
        name = f"ppt/slides/slide{next_no}.xml"
        text_files[name] = slide_xml
        text_files[f"ppt/slides/_rels/slide{next_no}.xml.rels"] = rels_for(chunk_xml)
        ctypes = ctypes.replace(
            "</Types>",
            f'<Override PartName="/{name}" ContentType="{SLIDE_CT}" /></Types>')
        max_rid += 1
        max_sld_id += 1
        pres_rels = pres_rels.replace(
            "</Relationships>",
            f'<Relationship Id="rId{max_rid}" Type="{SLIDE_REL}" Target="slides/slide{next_no}.xml" /></Relationships>')
        new_entries.append(f'<p:sldId id="{max_sld_id}" r:id="rId{max_rid}" />')
        next_no += 1

    anchor = re.search(r'<p:sldId id="\d+" r:id="%s" />' % ref_rid, pres).group(0)
    pres = pres.replace(anchor, anchor + "".join(new_entries), 1)
    text_files["ppt/presentation.xml"] = pres
    text_files["ppt/_rels/presentation.xml.rels"] = pres_rels
    text_files["[Content_Types].xml"] = ctypes

    tmp = PPTX.with_suffix(".tmp")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as out:
        written = set()
        for n in order:
            data = text_files[n].encode("utf-8") if n in text_files else files[n]
            out.writestr(n, data)
            written.add(n)
        for n in text_files:
            if n not in written:
                out.writestr(n, text_files[n].encode("utf-8"))
    tmp.replace(PPTX)
    print(f"split References into {len(chunks)} slides")


if __name__ == "__main__":
    main()
