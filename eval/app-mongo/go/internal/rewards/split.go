package rewards

import (
	"errors"
	"sort"
)

// Split divides pool minor units by integer weights. Shares always add up to the
// pool: the units left after flooring go to the largest remainders, ties by id.
func Split(pool int64, weights map[string]int64) (map[string]int64, error) {
	var total int64
	for _, w := range weights {
		if w < 0 {
			return nil, errors.New("negative weight")
		}
		total += w
	}
	if pool < 0 || total == 0 {
		return nil, errors.New("nothing to split")
	}

	type rem struct {
		id  string
		rem int64
	}
	shares := make(map[string]int64, len(weights))
	rems := make([]rem, 0, len(weights))
	var given int64
	for id, w := range weights {
		shares[id] = pool * w / total
		rems = append(rems, rem{id, pool * w % total})
		given += shares[id]
	}
	sort.Slice(rems, func(i, j int) bool {
		if rems[i].rem != rems[j].rem {
			return rems[i].rem > rems[j].rem
		}
		return rems[i].id < rems[j].id
	})
	for i := int64(0); i < pool-given; i++ {
		shares[rems[i].id]++
	}
	return shares, nil
}
