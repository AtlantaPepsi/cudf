/*
 * Copyright (c) 2019-2022, NVIDIA CORPORATION.
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

#include <cudf/column/column_view.hpp>
#include <cudf/copying.hpp>
#include <cudf/detail/copy.hpp>
#include <cudf/detail/iterator.cuh>
#include <cudf/detail/null_mask.cuh>
#include <cudf/detail/nvtx/ranges.hpp>
#include <cudf/utilities/error.hpp>

#include <rmm/cuda_stream_view.hpp>

#include <thrust/iterator/transform_iterator.h>

#include <algorithm>

namespace cudf {
namespace detail {
std::vector<column_view> slice(column_view const& input,
                               host_span<size_type const> indices,
                               rmm::cuda_stream_view stream)
{
  CUDF_EXPECTS(indices.size() % 2 == 0, "indices size must be even");

  if (indices.empty()) return {};

  // need to shift incoming indices by the column offset to generate the correct bit ranges
  // to count
  auto indices_iter = cudf::detail::make_counting_transform_iterator(
    0, [offset = input.offset(), &indices](size_type index) { return indices[index] + offset; });
  auto null_counts = cudf::detail::segmented_null_count(
    input.null_mask(), indices_iter, indices_iter + indices.size(), stream);

  auto const children = std::vector<column_view>(input.child_begin(), input.child_end());

  auto op = [&](auto i) {
    auto begin = indices[2 * i];
    auto end   = indices[2 * i + 1];
    CUDF_EXPECTS(begin >= 0, "Starting index cannot be negative.");
    CUDF_EXPECTS(end >= begin, "End index cannot be smaller than the starting index.");
    CUDF_EXPECTS(end <= input.size(), "Slice range out of bounds.");
    return column_view{input.type(),
                       end - begin,
                       input.head(),
                       input.null_mask(),
                       null_counts[i],
                       input.offset() + begin,
                       children};
  };
  auto begin = cudf::detail::make_counting_transform_iterator(0, op);
  return std::vector<column_view>{begin, begin + indices.size() / 2};
}

std::vector<table_view> slice(table_view const& input,
                              host_span<size_type const> indices,
                              rmm::cuda_stream_view stream)
{
  CUDF_EXPECTS(indices.size() % 2 == 0, "indices size must be even");
  if (indices.empty()) { return {}; }

  // 2d arrangement of column_views that represent the outgoing table_views sliced_table[i][j]
  // where i is the i'th column of the j'th table_view
  auto op = [&indices, &stream](auto const& c) { return cudf::detail::slice(c, indices, stream); };
  auto f  = thrust::make_transform_iterator(input.begin(), op);

  auto sliced_table = std::vector<std::vector<cudf::column_view>>(f, f + input.num_columns());
  sliced_table.reserve(indices.size() + 1);

  std::vector<cudf::table_view> result{};
  // distribute columns into outgoing table_views
  size_t num_output_tables = indices.size() / 2;
  for (size_t i = 0; i < num_output_tables; i++) {
    std::vector<cudf::column_view> table_columns;
    for (size_type j = 0; j < input.num_columns(); j++) {
      table_columns.emplace_back(sliced_table[j][i]);
    }
    result.emplace_back(table_view{table_columns});
  }

  return result;
}

std::vector<column_view> slice(column_view const& input,
                               std::initializer_list<size_type> indices,
                               rmm::cuda_stream_view stream)
{
  return slice(input, host_span<size_type const>(indices.begin(), indices.size()), stream);
}

std::vector<table_view> slice(table_view const& input,
                              std::initializer_list<size_type> indices,
                              rmm::cuda_stream_view stream)
{
  return slice(input, host_span<size_type const>(indices.begin(), indices.size()), stream);
};

}  // namespace detail

std::vector<column_view> slice(column_view const& input, host_span<size_type const> indices)
{
  CUDF_FUNC_RANGE();
  return detail::slice(input, indices, rmm::cuda_stream_default);
}

std::vector<table_view> slice(table_view const& input, host_span<size_type const> indices)
{
  CUDF_FUNC_RANGE();
  return detail::slice(input, indices, rmm::cuda_stream_default);
};

std::vector<column_view> slice(column_view const& input, std::initializer_list<size_type> indices)
{
  CUDF_FUNC_RANGE();
  return detail::slice(input, indices, rmm::cuda_stream_default);
}

std::vector<table_view> slice(table_view const& input, std::initializer_list<size_type> indices)
{
  CUDF_FUNC_RANGE();
  return detail::slice(input, indices, rmm::cuda_stream_default);
};

}  // namespace cudf
