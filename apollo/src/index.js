const fs = require("fs");
const path = require("path");

const apm = require("elastic-apm-node").start({
  serviceName: process.env.ELASTIC_APM_SERVICE_NAME || "apollo-server",
  serverUrl: process.env.ELASTIC_APM_SERVER_URL || "http://localhost:8200",
  environment: process.env.NODE_ENV || "lab",
  transactionSampleRate: Number(process.env.ELASTIC_APM_TRANSACTION_SAMPLE_RATE || "1.0"),
  captureBody: process.env.ELASTIC_APM_CAPTURE_BODY || "transactions",
  active: process.env.ELASTIC_APM_ACTIVE !== "false"
});

const { ApolloServer } = require("@apollo/server");
const { startStandaloneServer } = require("@apollo/server/standalone");
const pino = require("pino");

const logDir = path.join(__dirname, "..", "logs");
fs.mkdirSync(logDir, { recursive: true });

const logger = pino(
  {
    level: process.env.LOG_LEVEL || "info",
    base: {
      service: "apollo-server",
      environment: process.env.NODE_ENV || "lab"
    }
  },
  pino.multistream([
    { stream: process.stdout },
    { stream: pino.destination(path.join(logDir, "app.log")) }
  ])
);

const typeDefs = `#graphql
  type Book {
    title: String!
    author: String!
  }

  type Query {
    books: [Book!]!
    book(title: String!): Book
    health: String!
    slowBooks(delayMs: Int = 250): [Book!]!
  }
`;

const books = [
  { title: "The Awakening", author: "Kate Chopin" },
  { title: "City of Glass", author: "Paul Auster" },
  { title: "Clean Code", author: "Robert C. Martin" },
  { title: "Release It!", author: "Michael T. Nygard" }
];

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const resolvers = {
  Query: {
    books: (_parent, _args, context) => {
      context.logger.info({ operation: "books", resultCount: books.length }, "books resolver executed");
      return books;
    },
    book: (_parent, args, context) => {
      context.logger.info({ operation: "book", title: args.title }, "book resolver executed");
      return books.find((book) => book.title.toLowerCase() === args.title.toLowerCase()) || null;
    },
    health: () => "ok",
    slowBooks: async (_parent, args, context) => {
      const delayMs = Math.min(Number(args.delayMs || 250), 3000);
      const span = apm.startSpan("simulate catalog lookup", "app", "timer");
      await wait(delayMs);
      if (span) span.end();

      context.logger.warn({ operation: "slowBooks", delayMs }, "slow resolver executed");
      return books;
    }
  }
};

const apmPlugin = {
  async requestDidStart(requestContext) {
    const operationName = requestContext.request.operationName || "anonymous";
    const query = requestContext.request.query || "";
    const transaction = apm.currentTransaction;

    if (transaction) {
      transaction.setLabel("graphql_operation_name", operationName);
      transaction.setLabel("graphql_has_query", Boolean(query));
    }

    logger.info({ event: "graphql_request_start", operationName, query }, "GraphQL request received");

    return {
      async willSendResponse(ctx) {
        const status = ctx.errors && ctx.errors.length > 0 ? "error" : "ok";
        if (transaction) transaction.setLabel("graphql_result", status);

        logger.info(
          {
            event: "graphql_request_end",
            operationName,
            status,
            errors: ctx.errors ? ctx.errors.map((error) => error.message) : []
          },
          "GraphQL response sent"
        );
      },
      async didEncounterErrors(ctx) {
        for (const error of ctx.errors) {
          apm.captureError(error);
          logger.error({ event: "graphql_error", operationName, error: error.message }, "GraphQL error captured");
        }
      }
    };
  }
};

async function main() {
  const server = new ApolloServer({
    typeDefs,
    resolvers,
    plugins: [apmPlugin],
    introspection: true
  });

  const port = Number(process.env.PORT || "4000");
  const { url } = await startStandaloneServer(server, {
    listen: { host: "0.0.0.0", port },
    context: async () => ({ logger })
  });

  logger.info({ url }, "Apollo Server ready");
}

main().catch((error) => {
  apm.captureError(error);
  logger.fatal({ error: error.message, stack: error.stack }, "Apollo Server failed to start");
  process.exit(1);
});
