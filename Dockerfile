FROM maven:3-openjdk-11 as builder
COPY . /chesslib
WORKDIR /chesslib
# Build the library jar and download the dependencies
RUN mvn clean package && mvn dependency:copy-dependencies
# Copy the jar to the fuzz folder and copy the dependencies to the fuzz folder
RUN mkdir ./fuzz/deps && find ./target -name "chesslib*.jar" -exec cp {} "./fuzz/deps/chesslib.jar" \; && cp ./target/dependency/* ./fuzz/deps && python3 fuzz/generate_classpath.py > fuzz/src/Manifest.txt
WORKDIR /chesslib/fuzz/src
# Build the fuzz target
RUN javac -cp "../deps/*" fuzz_chess_board_loader.java && jar cfme fuzz_chess_board_loader.jar Manifest.txt fuzz_chess_board_loader fuzz_chess_board_loader.class && chmod u+x fuzz_chess_board_loader.jar && cp fuzz_chess_board_loader.jar /chesslib/fuzz/deps
WORKDIR /chesslib/fuzz/deps
