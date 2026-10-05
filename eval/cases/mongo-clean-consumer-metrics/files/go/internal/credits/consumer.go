package credits

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/segmentio/kafka-go"
)

type paymentPaid struct {
	EventID  string `json:"event_id"`
	Type     string `json:"type"`
	UserID   string `json:"user_id"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
}

// Consumer grants 1% cashback for paid payments. The offset is committed only after
// the credit, and the credit is idempotent by event id.
type Consumer struct {
	Reader *kafka.Reader
	Store  *Store
}

const cashbackBasisPoints = 100

var cashbackEvents = prometheus.NewCounterVec(prometheus.CounterOpts{
	Name: "billing_cashback_events_total",
	Help: "Payment events seen by the cashback consumer, by outcome.",
}, []string{"outcome"})

func (c *Consumer) Run(ctx context.Context) error {
	for {
		msg, err := c.Reader.FetchMessage(ctx)
		if err != nil {
			return err
		}
		if err := c.apply(ctx, msg.Value); err != nil {
			return fmt.Errorf("offset %d: %w", msg.Offset, err) // no commit: redelivered after restart
		}
		if err := c.Reader.CommitMessages(ctx, msg); err != nil {
			return err
		}
	}
}

func (c *Consumer) apply(ctx context.Context, value []byte) error {
	var ev paymentPaid
	if err := json.Unmarshal(value, &ev); err != nil {
		return err
	}
	if ev.Type != "payment.paid" {
		cashbackEvents.WithLabelValues("skipped").Inc()
		return nil
	}
	cashback := ev.Amount * cashbackBasisPoints / 10_000
	if cashback == 0 {
		return nil
	}
	budget := "cashback_budget:" + ev.Currency
	wallet := "user:" + ev.UserID + ":" + ev.Currency
	if err := c.Store.Transfer(ctx, budget, wallet, cashback, ev.Currency, "cashback:"+ev.EventID); err != nil {
		return err
	}
	cashbackEvents.WithLabelValues("credited").Inc()
	return nil
}
