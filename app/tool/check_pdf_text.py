"""Print the text a PDF reader extracts from each page (checks the searchable layer).

../backend/.venv/bin/python tool/check_pdf_text.py build/test_hindi.pdf
"""

import sys

import pypdfium2 as pdfium

for path in sys.argv[1:]:
    doc = pdfium.PdfDocument(path)
    for i, page in enumerate(doc):
        print(f"{path} page {i + 1}: {page.get_textpage().get_text_range()!r}")
