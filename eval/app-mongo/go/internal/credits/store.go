package credits

import (
	"context"
	"errors"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

// ErrInsufficientFunds means the source wallet cannot pay the amount.
var ErrInsufficientFunds = errors.New("insufficient funds")

// Store moves cashback between wallets. Amounts are int64 minor units. Every
// transfer writes one ledger entry whose _id is the idempotency key.
type Store struct {
	client  *mongo.Client
	wallets *mongo.Collection
	entries *mongo.Collection
}

func NewStore(client *mongo.Client) *Store {
	db := client.Database("billing")
	return &Store{client: client, wallets: db.Collection("wallets"), entries: db.Collection("ledger_entries")}
}

// Transfer moves amount from one wallet to another once per key. A repeated key is
// a no-op. A failed write aborts a MongoDB transaction, so the key is checked with a
// read in the session instead of by catching a duplicate key error.
func (s *Store) Transfer(ctx context.Context, from, to string, amount int64, currency, key string) error {
	if amount <= 0 {
		return errors.New("amount must be positive")
	}
	session, err := s.client.StartSession()
	if err != nil {
		return err
	}
	defer session.EndSession(ctx)

	_, err = session.WithTransaction(ctx, func(sc mongo.SessionContext) (any, error) {
		err := s.entries.FindOne(sc, bson.M{"_id": key}).Err()
		if err == nil {
			return nil, nil // already transferred under this key
		}
		if !errors.Is(err, mongo.ErrNoDocuments) {
			return nil, err
		}
		if _, err := s.entries.InsertOne(sc, bson.M{
			"_id": key, "from": from, "to": to, "amount": amount, "currency": currency, "created_at": time.Now(),
		}); err != nil {
			return nil, err
		}
		debit, err := s.wallets.UpdateOne(sc,
			bson.M{"_id": from, "currency": currency, "balance": bson.M{"$gte": amount}},
			bson.M{"$inc": bson.M{"balance": -amount}})
		if err != nil {
			return nil, err
		}
		if debit.ModifiedCount == 0 {
			return nil, ErrInsufficientFunds
		}
		credit, err := s.wallets.UpdateOne(sc,
			bson.M{"_id": to, "currency": currency},
			bson.M{"$inc": bson.M{"balance": amount}})
		if err != nil {
			return nil, err
		}
		if credit.MatchedCount == 0 {
			return nil, errors.New("wallet not found: " + to)
		}
		return nil, nil
	})
	return err
}
