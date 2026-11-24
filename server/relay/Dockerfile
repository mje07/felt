# Build a small native binary, then run it on a minimal image.
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY . .
RUN dart pub get --offline && dart compile exe bin/relay.dart -o /app/relay

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/relay /app/relay
ENV PORT=8080
EXPOSE 8080
CMD ["/app/relay"]
