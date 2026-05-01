Subject: AI Search Architecture - Options Analysis for UDIP Analytics Platform

Siva,

Following up on the discussion about search and vectorization for the analytics platform. I looked at all four options and want to lay out the tradeoffs so we can make an informed decision on direction. This is the data layer that powers AI-assisted case analysis, the conversational AI assistant, and the RAG pipeline for legal document retrieval across ADR, Triage, OGC, and UDIP.

---

**Option 1: PostgreSQL with pgvector (our proposed path)**

PostgreSQL is the same database engine ARC runs on (PrEPA). The pgvector extension adds vector similarity search directly inside PostgreSQL, so structured data queries, full-text search, and AI vector search all happen in one database.

Pros:
- Single database for everything. No data synchronization problems between systems.
- Row-level security enforced at the database layer. An analyst in District 15 cannot retrieve vectors belonging to District 22. This is automatic, not application-enforced.
- Real-time data via WAL/CDC from PrEPA. No polling delay.
- Transactional consistency. When a case is updated, the vector index reflects it immediately, not 10 seconds later.
- FOIA and NARA 7-year retention controls built into the same database lifecycle.
- No additional infrastructure cost. pgvector is a free PostgreSQL extension already available on Azure Database for PostgreSQL.
- PgBouncer connection pooling gives us 3,000 concurrent client connections.

Cons:
- Single-node vector search. If we ever need billions of vectors with distributed sharding, PostgreSQL would not be the right tool. At our data volume (roughly 800GB, around 10,000 document chunks for RAG), this is not a concern.
- Less mature ecosystem than Elasticsearch for complex text analytics like faceted aggregation across millions of documents.

Estimated timeline: 4-5 months to build the full analytics platform with AI assistant, RAG pipeline, case-scoped vector search, and the compliance controls.

---

**Option 2: Elasticsearch (leverage ARC's existing cluster or stand up our own)**

ARC currently runs Elasticsearch 9.1.5 on Kubernetes via ECK. I reviewed the SearchDataWebService source code and index mappings. Today, it polls PrEPA every 10-300 seconds and indexes charge data for the search bar in the Angular UI. It uses keyword and wildcard search only. No vector embeddings, no kNN queries, no dense_vector fields, no semantic search. None of the 6 indices have vector mappings. There is no embedding pipeline. There is no Azure OpenAI integration. The Elasticsearch instance is a keyword search box for case lookups.

Upgrading the Elasticsearch version does not change this. The upgrade gives the engine the theoretical ability to store vectors, but it does not create the vectors, build the pipeline to generate them, or add the query logic to use them. That is new development work, not a configuration change.

To actually use Elasticsearch for AI-powered vector search, someone would need to:
- Build an embedding pipeline that calls Azure OpenAI on every indexed document and stores the resulting vector (new microservice or major rework of SearchDataWebService)
- Redesign all 6 index mappings to add dense_vector fields and reindex all existing data
- Build new kNN query endpoints and hybrid search logic combining keyword relevance with vector similarity
- Re-implement row-level security as Elasticsearch query filters (Elasticsearch does not have native RLS like PostgreSQL)
- Build HMAC audit logging, FOIA export, litigation hold integration, and 7-year WORM retention separately since these are not Elasticsearch features
- Modify the Angular frontend to consume the new search API

If we use ARC's existing cluster, that work falls on ARC's contractor team. If we stand up our own Elasticsearch cluster, we own the work but also own another piece of infrastructure.

Pros:
- Distributed architecture scales to very large document corpuses.
- In-memory vector indices can be fast for high-concurrency vector search.
- ARC already operates an Elasticsearch cluster, so the infrastructure team has experience with it.

Cons:
- Two data stores to keep in sync. Data lives in PostgreSQL (source of truth) AND Elasticsearch (search index). Sync lag means search results can be stale.
- No native row-level security. Every access control policy must be re-implemented as query-time filters. If a filter is missed, data leaks.
- No built-in audit integrity, FOIA retention, or litigation hold support. All of that is custom work.
- Additional cost. A production Elasticsearch cluster on Azure Government runs roughly $250-500/month for our data volume, plus engineering to build and maintain the sync pipeline.
- ARC's Elasticsearch is managed by a separate contractor. Any changes to the index structure or query API require coordination with their team and their release cycle.
- The version upgrade adds the vector engine capability but none of the implementation. The embedding pipeline, kNN query layer, hybrid search logic, access controls, audit logging, FOIA retention, and litigation hold integration all need to be designed and built from scratch. That work alone is 6-9 months of engineering, not including the compliance controls that would need to be layered on top. The Elasticsearch path is not faster than building on PostgreSQL. It is slower, because none of the compliance infrastructure exists yet in ARC's Elasticsearch stack.
- Cost estimate for the Elasticsearch path: $250-500/month for the infrastructure plus roughly 6-9 months of contractor engineering time at $250-300/hour blended rate. That is $500K-$900K in development costs on top of the infrastructure, and it still would not include row-level security, FOIA retention, or HMAC audit integrity since those are not Elasticsearch features.

---

**Option 3: Fix IDR**

IDR is the existing reporting database that mirrors ARC data for BI purposes. It runs PostgreSQL but is undersized (roughly 20 concurrent connections) and uses ARC's transactional schema without any denormalization.

Pros:
- Already exists.
- Already inside the FedRAMP boundary.

Cons:
- 20 connection ceiling. Our platform needs thousands of concurrent connections.
- No connection pooling layer.
- Normalized transactional schema not designed for analytical queries. Queries that join 5-10 tables take 30 seconds instead of under 1 second on a denormalized schema.
- No vector search (no pgvector).
- No row-level security.
- Nightly batch ETL, not real-time CDC.
- No AI capabilities.
- Fixing these problems means adding PgBouncer, pgvector, RLS policies, a denormalized schema, and real-time CDC. At that point, you have rebuilt the system from scratch. The end result would be functionally identical to Option 1.

---

**Option 4: Azure Data Factory**

I want to make sure we are on the same page about what Data Factory is. Azure Data Factory is a pipeline orchestration tool for moving and transforming data between sources. It is not a database and it is not a search engine. It can copy data from PrEPA into another system, but you still need that other system to query and search.

Pros:
- Good for batch ETL and scheduled data movement.
- Visual pipeline designer for data transformations.
- Managed service, low operational overhead.

Cons:
- Does not replace a database or search engine. You still need PostgreSQL, Elasticsearch, or something else to store and query the data.
- Batch-oriented. Real-time CDC via Debezium and Event Hub (which we would use) is faster and lower cost than ADF's streaming option.
- Would be supplementary to our architecture, not a replacement for any part of it.

---

**Why PostgreSQL + pgvector is the right path**

The core question is whether the AI search capabilities we need are better served by adding Elasticsearch as a second data store or by using pgvector inside the PostgreSQL database we already need for structured data, CDC, row-level security, and compliance controls.

At our scale, pgvector handles vector search with the same HNSW algorithm Elasticsearch uses. The performance difference is measurable only at scales we will not reach (millions of concurrent vector queries per second across billions of documents). What we do need at our scale is transactional consistency, row-level security on search results, FOIA-compliant audit trails, and case-scoped data isolation. Those are database features, not search engine features.

Adding Elasticsearch means maintaining two data stores, building a synchronization layer, re-implementing access controls outside the database, and adding another component to the FedRAMP authorization boundary. For the same cost and timeline, we can build the full platform on PostgreSQL with pgvector and have one system to secure, one system to audit, and one system to maintain.

If our data volume grows significantly in the future and we need distributed vector search beyond what pgvector can handle, we can add Azure AI Search as a read-only search layer at that point without reworking the foundation. The architecture supports it.

Happy to walk through any of this in more detail. I can also put together a more formal comparison document if that would be useful for the AIGB review.

Derek
