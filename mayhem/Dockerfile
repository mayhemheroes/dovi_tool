# Build Stage
FROM ghcr.io/evanrichter/cargo-fuzz:latest as builder

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses && \
    bash -c "pushd dolby_vision/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    mv dolby_vision/fuzz/target/x86_64-unknown-linux-gnu/release/parse_itu_t35_dashif /parse_itu_t35_dashif && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd dolby_vision/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    mv dolby_vision/fuzz/target/release/parse_itu_t35_dashif /parse_itu_t35_dashif_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /parse_itu_t35_dashif /parse_itu_t35_dashif_no_inst /
