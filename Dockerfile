# Use the official Dart SDK image.
FROM dart:stable AS build

# Resolve app dependencies.
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get

# Copy app source code and AOT compile it.
COPY . .
# Ensure packages are still in sync
RUN dart pub get --offline
RUN dart compile exe bin/household_chore_management.dart -o bin/server

# Build minimal runtime image from buster-slim.
FROM debian:buster-slim

# Copy the compiled binary from build stage
COPY --from=build /app/bin/server /app/bin/server

# Set working directory
WORKDIR /app

# Run the server
CMD ["/app/bin/server"]
