package rewards

import (
	"context"
	"fmt"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"example.com/billing-worker/internal/credits"
)

// Referrers get 2% of what the users they brought paid in a month.
const referralBasisPoints = 200

// Payments are read in batches so that one month does not hold a cursor open for
// minutes while the transfers run.
const referralBatch = 500

// ReferralRun pays the monthly referral bonus from the referral budget wallet.
type ReferralRun struct {
	Payments *mongo.Collection
	Store    *credits.Store
}

type referredPayment struct {
	ID         string `bson:"_id"`
	ReferredBy string `bson:"referred_by"`
	Amount     int64  `bson:"amount"`
	Currency   string `bson:"currency"`
}

// PayMonth credits the referrers for payments made in the calendar month that starts
// at monthStart (UTC, the first day at 00:00). Safe to re-run for the same month: the
// ledger key is the payment id. Returns the number of bonuses paid by this run.
func (r *ReferralRun) PayMonth(ctx context.Context, monthStart time.Time) (int, error) {
	if monthStart.Day() != 1 || !monthStart.Equal(monthStart.Truncate(24*time.Hour)) {
		return 0, fmt.Errorf("month start %s is not the first day at midnight", monthStart)
	}
	end := monthStart.AddDate(0, 1, 0)

	filter := bson.M{
		"status":      "paid",
		"referred_by": bson.M{"$exists": true, "$ne": ""},
		"paid_at":     bson.M{"$gte": monthStart, "$lt": end},
	}
	opts := options.Find().
		SetSort(bson.D{{Key: "_id", Value: 1}}).
		SetLimit(referralBatch)

	cur, err := r.Payments.Find(ctx, filter, opts)
	if err != nil {
		return 0, err
	}
	defer cur.Close(ctx)

	paid := 0
	for cur.Next(ctx) {
		var p referredPayment
		if err := cur.Decode(&p); err != nil {
			return paid, err
		}
		bonus := p.Amount * referralBasisPoints / 10_000
		if bonus == 0 {
			continue
		}
		budget := "referral_budget:" + p.Currency
		wallet := "user:" + p.ReferredBy + ":" + p.Currency
		if err := r.Store.Transfer(ctx, budget, wallet, bonus, p.Currency, "referral:"+p.ID); err != nil {
			return paid, fmt.Errorf("payment %s: %w", p.ID, err)
		}
		paid++
	}
	return paid, cur.Err()
}
