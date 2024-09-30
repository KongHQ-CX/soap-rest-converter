FROM kong/kong-gateway:3.8.0.0

# Ensure any patching steps are executed as root user
USER root

# Define architecture (ex: amd64, arm64, arm, ...)
ARG TARGETARCH

# Add custom plugin to the image
COPY ./kong/plugins/soap-rest-converter /usr/local/share/lua/5.1/kong/plugins/soap-rest-converter
COPY ./kong/saxon/so/$TARGETARCH /usr/local/lib/kongsaxon

# Set environment variables for Kong
ENV KONG_PLUGINS=bundled,soap-rest-converter
ENV LD_LIBRARY_PATH=/usr/local/lib/kongsaxon

# Ensure kong user is selected for image execution
USER kong

# Run kong
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 8000 8443 8001 8444
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=10s --timeout=10s --retries=10 CMD kong health
CMD ["kong", "docker-start"]