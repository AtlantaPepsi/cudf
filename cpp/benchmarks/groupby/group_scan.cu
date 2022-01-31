/*
 * Copyright (c) 2022, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <benchmarks/fixture/benchmark_fixture.hpp>
#include <benchmarks/groupby/group_common.hpp>
#include <benchmarks/synchronization/synchronization.hpp>

#include <cudf/copying.hpp>
#include <cudf/detail/aggregation/aggregation.hpp>
#include <cudf/groupby.hpp>
#include <cudf/sorting.hpp>
#include <cudf/table/table.hpp>

#include <cudf_test/column_wrapper.hpp>

class Groupby : public cudf::benchmark {
};

void BM_basic_sum_scan(benchmark::State& state)
{
  using wrapper = cudf::test::fixed_width_column_wrapper<int64_t>;

  const cudf::size_type column_size{(cudf::size_type)state.range(0)};

  auto data_it = cudf::detail::make_counting_transform_iterator(
    0, [=](cudf::size_type row) { return random_int(0, 100); });

  wrapper keys(data_it, data_it + column_size);
  wrapper vals(data_it, data_it + column_size);

  cudf::groupby::groupby gb_obj(cudf::table_view({keys, keys, keys}));

  std::vector<cudf::groupby::scan_request> requests;
  requests.emplace_back(cudf::groupby::scan_request());
  requests[0].values = vals;
  requests[0].aggregations.push_back(cudf::make_sum_aggregation<cudf::groupby_scan_aggregation>());

  for (auto _ : state) {
    cuda_event_timer timer(state, true);

    auto result = gb_obj.scan(requests);
  }
}

BENCHMARK_DEFINE_F(Groupby, BasicSumScan)(::benchmark::State& state) { BM_basic_sum_scan(state); }

BENCHMARK_REGISTER_F(Groupby, BasicSumScan)
  ->UseManualTime()
  ->Unit(benchmark::kMillisecond)
  ->Arg(1000000)
  ->Arg(10000000)
  ->Arg(100000000);

void BM_pre_sorted_sum_scan(benchmark::State& state)
{
  using wrapper = cudf::test::fixed_width_column_wrapper<int64_t>;

  const cudf::size_type column_size{(cudf::size_type)state.range(0)};

  auto data_it = cudf::detail::make_counting_transform_iterator(
    0, [=](cudf::size_type row) { return random_int(0, 100); });
  auto valid_it = cudf::detail::make_counting_transform_iterator(
    0, [=](cudf::size_type row) { return random_int(0, 100) < 90; });

  wrapper keys(data_it, data_it + column_size);
  wrapper vals(data_it, data_it + column_size, valid_it);

  auto keys_table  = cudf::table_view({keys});
  auto sort_order  = cudf::sorted_order(keys_table);
  auto sorted_keys = cudf::gather(keys_table, *sort_order);
  // No need to sort values using sort_order because they were generated randomly

  cudf::groupby::groupby gb_obj(*sorted_keys, cudf::null_policy::EXCLUDE, cudf::sorted::YES);

  std::vector<cudf::groupby::scan_request> requests;
  requests.emplace_back(cudf::groupby::scan_request());
  requests[0].values = vals;
  requests[0].aggregations.push_back(cudf::make_sum_aggregation<cudf::groupby_scan_aggregation>());

  for (auto _ : state) {
    cuda_event_timer timer(state, true);

    auto result = gb_obj.scan(requests);
  }
}

BENCHMARK_DEFINE_F(Groupby, PreSortedSumScan)(::benchmark::State& state)
{
  BM_pre_sorted_sum_scan(state);
}

BENCHMARK_REGISTER_F(Groupby, PreSortedSumScan)
  ->UseManualTime()
  ->Unit(benchmark::kMillisecond)
  ->Arg(1000000)
  ->Arg(10000000)
  ->Arg(100000000);