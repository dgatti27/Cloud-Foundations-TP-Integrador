from .erp_foxpro import extract_erp
from .ecommerce_mongo import extract_ecommerce
from .eventos_mongo import extract_eventos
from .scraping import extract_scraping

EXTRACTORS = {
    "erp-foxpro": extract_erp,
    "ecommerce-mongo": extract_ecommerce,
    "eventos-mongo": extract_eventos,
    "scraping": extract_scraping,
}
