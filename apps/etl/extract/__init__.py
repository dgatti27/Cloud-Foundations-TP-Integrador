from .erp_foxpro import extract_erp, extract_erp_all
from .from_bronce import extract_bronce, extract_bronce_all
from .ecommerce_mongo import extract_ecommerce
from .eventos_mongo import extract_eventos
from .scraping import extract_scraping

EXTRACTORS = {
    "erp": extract_erp,
    "erp-foxpro": extract_erp,  # alias histórico
    "bronce": extract_bronce,
    "ecommerce-mongo": extract_ecommerce,
    "eventos-mongo": extract_eventos,
    "scraping": extract_scraping,
}

__all__ = [
    "EXTRACTORS",
    "extract_erp",
    "extract_erp_all",
    "extract_bronce",
    "extract_bronce_all",
    "extract_ecommerce",
    "extract_eventos",
    "extract_scraping",
]
