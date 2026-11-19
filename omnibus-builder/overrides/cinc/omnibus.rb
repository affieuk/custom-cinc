# Optional Cinc Omnibus component overrides.
#
# Uncomment/change only what you intentionally want to replace from upstream.
# These statements are appended to chef/omnibus/omnibus.rb before the product
# build. Omnibus' later override for a component wins.
#
# Examples:
# override :ruby, version: "3.4.11"
# override :openssl, version: "3.6.5"
#
# Ruby/OpenSSL combinations sometimes also require an openssl gem override; use
# normal Omnibus syntax here when the selected omnibus-software release needs it:
# override :ruby, version: "3.4.11", openssl_gem: "3.3.2"
