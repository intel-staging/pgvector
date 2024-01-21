use strict;
use warnings;
use PostgresNode;
use TestLib;
use Test::More;

my $dim = 3;
my $nc = 50;
my $limit = 20;

my $array_sql = join(",", ('random()') x $dim);

# Initialize node
my $node = get_new_node('node');
$node->init;
$node->start;

# Create table and index
$node->safe_psql("postgres", "CREATE EXTENSION vector;");
$node->safe_psql("postgres", "CREATE TABLE tst (i int4, v vector($dim), c int4);");
$node->safe_psql("postgres",
	"INSERT INTO tst SELECT i, ARRAY[$array_sql], i % $nc FROM generate_series(1, 10000) i;"
);
$node->safe_psql("postgres", "CREATE INDEX idx ON tst USING ivfflat (v vector_l2_ops) WITH (lists = 100);");

# Generate query
my @r = ();
for (1 .. $dim)
{
	push(@r, rand());
}
my $query = "[" . join(",", @r) . "]";
my $c = int(rand() * $nc);

# Test attribute filtering
my $explain = $node->safe_psql("postgres", qq(
	EXPLAIN ANALYZE SELECT i FROM tst WHERE c = $c ORDER BY v <-> '$query' LIMIT $limit;
));
# TODO Do not use index
like($explain, qr/Index Scan using idx/);

# Test attribute filtering with few rows removed
$explain = $node->safe_psql("postgres", qq(
	EXPLAIN ANALYZE SELECT i FROM tst WHERE c != $c ORDER BY v <-> '$query' LIMIT $limit;
));
like($explain, qr/Index Scan using idx/);

# Test distance filtering
$explain = $node->safe_psql("postgres", qq(
	EXPLAIN ANALYZE SELECT i FROM tst WHERE v <-> '$query' < 1 ORDER BY v <-> '$query' LIMIT $limit;
));
like($explain, qr/Index Scan using idx/);

# Test distance filtering greater than distance
$explain = $node->safe_psql("postgres", qq(
	EXPLAIN ANALYZE SELECT i FROM tst WHERE v <-> '$query' > 1 ORDER BY v <-> '$query' LIMIT $limit;
));
# TODO Do not use index
like($explain, qr/Index Scan using idx/);

# Test distance filtering without order
$explain = $node->safe_psql("postgres", qq(
	EXPLAIN ANALYZE SELECT i FROM tst WHERE v <-> '$query' < 1;
));
like($explain, qr/Seq Scan/);

# Test distance filtering without limit
$explain = $node->safe_psql("postgres", qq(
	EXPLAIN ANALYZE SELECT i FROM tst WHERE v <-> '$query' < 1 ORDER BY v <-> '$query';
));
# TODO Do not use index
like($explain, qr/Index Scan using idx/);

# Test attribute index
$node->safe_psql("postgres", "CREATE INDEX attribute_idx ON tst (c);");
$explain = $node->safe_psql("postgres", qq(
	EXPLAIN ANALYZE SELECT i FROM tst WHERE c = $c ORDER BY v <-> '$query' LIMIT $limit;
));
like($explain, qr/Bitmap Index Scan on attribute_idx/);

# Test partial index
$node->safe_psql("postgres", "CREATE INDEX partial_idx ON tst USING ivfflat (v vector_l2_ops) WITH (lists = 5) WHERE (c = $c);");
$explain = $node->safe_psql("postgres", qq(
	EXPLAIN ANALYZE SELECT i FROM tst WHERE c = $c ORDER BY v <-> '$query' LIMIT $limit;
));
like($explain, qr/Index Scan using partial_idx/);

done_testing();