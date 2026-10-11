# Elasticsearch for Temporal's visibility store (Postiz Railway template).
#
# Official image, plus:
#   - elasticsearch.yml / roles.yml for a private, single-node, password-protected node
#   - a small entrypoint that fixes ownership of the Railway volume (mounted as root)
#     and then drops to the image's elasticsearch user (uid 1000) before starting.
#
# 8.19 is the supported 8.x line (Temporal supports Elasticsearch v7 and v8;
# 7.17, used by the upstream Postiz compose file, reached end of life on 2026-01-15).

FROM docker.elastic.co/elasticsearch/elasticsearch:8.19.23

USER 0

COPY --chown=1000:0 --chmod=0660 elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml
COPY --chown=1000:0 --chmod=0660 roles.yml /usr/share/elasticsearch/config/roles.yml
COPY --chmod=0555 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/railway-entrypoint.sh"]
CMD ["eswrapper"]
